from __future__ import annotations

import hashlib
import os
import re
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.graphics.shapes import Circle, Drawing, Line, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    BaseDocTemplate,
    Flowable,
    Frame,
    Image,
    KeepTogether,
    ListFlowable,
    ListItem,
    LongTable,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output" / "pdf" / "smart_stand_complete_project_reference.pdf"
IMAGE_DIR = ROOT / "tmp" / "pdfs" / "hand_images"
THRESHOLD_FILE = (
    ROOT
    / "lib"
    / "hand_gesture_features"
    / "domain"
    / "constants"
    / "hand_gesture_thresholds.dart"
)

INK = colors.HexColor("#142B3A")
BLUE = colors.HexColor("#176B87")
BLUE_DARK = colors.HexColor("#0B3A53")
CYAN = colors.HexColor("#64CCC5")
PALE = colors.HexColor("#EAF6F6")
PALE_BLUE = colors.HexColor("#EDF5FA")
ORANGE = colors.HexColor("#F29F58")
RED = colors.HexColor("#C64040")
GREEN = colors.HexColor("#2E8B57")
MID = colors.HexColor("#637887")
GRID = colors.HexColor("#C7D5DD")
PAPER = colors.HexColor("#FBFCFD")


def ascii_text(value: object) -> str:
    """Normalize punctuation so the generated PDF uses ASCII hyphens."""
    text = str(value)
    replacements = {
        "\u2013": "-",
        "\u2014": "-",
        "\u2212": "-",
        "\u2192": "->",
        "\u2190": "<-",
        "\u2026": "...",
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u00a0": " ",
    }
    for source, target in replacements.items():
        text = text.replace(source, target)
    return text


def para(text: object, style: ParagraphStyle) -> Paragraph:
    value = escape(ascii_text(text)).replace("\n", "<br/>")
    return Paragraph(value, style)


def rich_para(text: str, style: ParagraphStyle) -> Paragraph:
    """Paragraph for trusted, generator-owned ReportLab markup."""
    return Paragraph(ascii_text(text), style)


def bullet_list(items: list[str], styles, compact: bool = False) -> ListFlowable:
    style = styles["BodyTiny"] if compact else styles["BodySmall"]
    return ListFlowable(
        [ListItem(para(item, style), leftIndent=5) for item in items],
        bulletType="bullet",
        leftIndent=13,
        bulletFontSize=5.5,
        spaceBefore=2,
        spaceAfter=5,
    )


def numbered_list(items: list[str], styles) -> ListFlowable:
    return ListFlowable(
        [ListItem(para(item, styles["BodySmall"]), leftIndent=6) for item in items],
        bulletType="1",
        start="1",
        leftIndent=18,
        bulletFontSize=7,
        spaceBefore=2,
        spaceAfter=5,
    )


def data_table(
    rows: list[list[object]],
    styles,
    widths: list[float] | None = None,
    header: bool = True,
    font_size: str = "TableCell",
    long: bool = False,
) -> Table:
    cooked: list[list[object]] = []
    for row_index, row in enumerate(rows):
        row_style = styles["TableHead"] if header and row_index == 0 else styles[font_size]
        cooked.append([
            value if isinstance(value, Flowable) else para(value, row_style)
            for value in row
        ])
    cls = LongTable if long else Table
    table = cls(
        cooked,
        colWidths=widths,
        repeatRows=1 if header else 0,
        hAlign="LEFT",
    )
    commands = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.35, GRID),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("BACKGROUND", (0, 0), (-1, 0), BLUE_DARK if header else colors.white),
    ]
    if header:
        for row_index in range(1, len(cooked)):
            if row_index % 2 == 0:
                commands.append(("BACKGROUND", (0, row_index), (-1, row_index), PALE_BLUE))
    table.setStyle(TableStyle(commands))
    return table


def key_value_table(rows: list[tuple[str, object]], styles) -> Table:
    cooked: list[list[object]] = []
    for label, value in rows:
        body = value if isinstance(value, Flowable) else para(value, styles["BodySmall"])
        cooked.append([para(label, styles["FieldLabel"]), body])
    table = Table(cooked, colWidths=[40 * mm, 127 * mm], hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("GRID", (0, 0), (-1, -1), 0.35, GRID),
                ("BACKGROUND", (0, 0), (0, -1), PALE_BLUE),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def callout(title: str, body: str, styles, color=BLUE) -> Table:
    content = [
        para(title, styles["CalloutTitle"]),
        para(body, styles["BodySmall"]),
    ]
    table = Table([[content]], colWidths=[167 * mm], hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), colors.Color(color.red, color.green, color.blue, alpha=0.08)),
                ("BOX", (0, 0), (-1, -1), 0.7, color),
                ("LINEBEFORE", (0, 0), (0, -1), 4, color),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    return table


def source_line(paths: list[str], styles) -> Paragraph:
    return para("Source: " + "; ".join(paths), styles["Source"])


def image_card(
    filename: str,
    caption: str,
    styles,
    width: float = 70 * mm,
    height: float = 48 * mm,
) -> Table:
    path = IMAGE_DIR / filename
    if not path.exists():
        return callout("Image unavailable", f"Expected image: {path}", styles, RED)
    image = Image(str(path))
    image._restrictSize(width, height)
    table = Table(
        [[image], [para(caption, styles["Caption"]) ]],
        colWidths=[width + 4 * mm],
        hAlign="LEFT",
    )
    table.setStyle(
        TableStyle(
            [
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("BOX", (0, 0), (-1, -1), 0.5, GRID),
                ("BACKGROUND", (0, 0), (-1, -1), colors.white),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    return table


class PipelineDiagram(Flowable):
    def __init__(self, width: float = 167 * mm, height: float = 64 * mm):
        super().__init__()
        self.width = width
        self.height = height

    def draw(self) -> None:
        canvas = self.canv
        box_w = 36 * mm
        box_h = 14 * mm
        x_positions = [0, 43 * mm, 86 * mm, 129 * mm]
        top = self.height - box_h
        labels = [
            "Camera frame",
            "Rotation / scale",
            "Hand + face + object ML",
            "Normalized preview space",
        ]
        fills = [PALE_BLUE, PALE, PALE_BLUE, PALE]
        for x, label, fill in zip(x_positions, labels, fills):
            canvas.setFillColor(fill)
            canvas.setStrokeColor(BLUE)
            canvas.roundRect(x, top, box_w, box_h, 3 * mm, fill=1, stroke=1)
            canvas.setFillColor(INK)
            canvas.setFont("Helvetica-Bold", 7.2)
            words = label.split(" ")
            mid = max(1, len(words) // 2)
            line1 = " ".join(words[:mid])
            line2 = " ".join(words[mid:])
            canvas.drawCentredString(x + box_w / 2, top + 8.5 * mm, line1)
            canvas.drawCentredString(x + box_w / 2, top + 4.8 * mm, line2)
        canvas.setStrokeColor(MID)
        canvas.setFillColor(MID)
        for x in x_positions[:-1]:
            x1 = x + box_w
            x2 = x + 43 * mm
            y = top + box_h / 2
            canvas.line(x1 + 1 * mm, y, x2 - 2 * mm, y)
            canvas.line(x2 - 4 * mm, y + 1.5 * mm, x2 - 2 * mm, y)
            canvas.line(x2 - 4 * mm, y - 1.5 * mm, x2 - 2 * mm, y)

        lower_y = 3 * mm
        lower_labels = [
            "Gesture priority\nstate machines",
            "Camera zoom / record",
            "Face-object selection\nand tracking",
            "UI overlays + point-8\ndwell input",
        ]
        for x, label in zip(x_positions, lower_labels):
            canvas.setFillColor(colors.white)
            canvas.setStrokeColor(ORANGE)
            canvas.roundRect(x, lower_y, box_w, box_h, 3 * mm, fill=1, stroke=1)
            canvas.setFillColor(INK)
            canvas.setFont("Helvetica-Bold", 7.1)
            label_lines = label.split("\n", 1)
            first = label_lines[0]
            second = label_lines[1] if len(label_lines) > 1 else ""
            canvas.drawCentredString(x + box_w / 2, lower_y + 8.5 * mm, first)
            canvas.drawCentredString(x + box_w / 2, lower_y + 4.8 * mm, second)
        canvas.setStrokeColor(MID)
        for x in x_positions:
            center_x = x + box_w / 2
            canvas.line(center_x, top - 1 * mm, center_x, lower_y + box_h + 2 * mm)
            canvas.line(center_x - 1.5 * mm, lower_y + box_h + 4 * mm, center_x, lower_y + box_h + 2 * mm)
            canvas.line(center_x + 1.5 * mm, lower_y + box_h + 4 * mm, center_x, lower_y + box_h + 2 * mm)


def landmark_drawing() -> Drawing:
    drawing = Drawing(167 * mm, 82 * mm)
    drawing.add(Rect(0, 0, 167 * mm, 82 * mm, fillColor=colors.white, strokeColor=GRID))
    points = {
        0: (82, 18),
        1: (58, 28), 2: (44, 38), 3: (31, 47), 4: (17, 51),
        5: (70, 46), 6: (68, 64), 7: (67, 79), 8: (66, 94),
        9: (83, 48), 10: (83, 70), 11: (83, 90), 12: (83, 108),
        13: (96, 46), 14: (99, 66), 15: (101, 83), 16: (103, 98),
        17: (108, 41), 18: (116, 56), 19: (122, 69), 20: (128, 80),
    }
    scale = 1.55
    ox = 8 * mm
    oy = 4 * mm
    converted = {k: (ox + x * scale, oy + y * scale) for k, (x, y) in points.items()}
    chains = [
        [0, 1, 2, 3, 4],
        [0, 5, 6, 7, 8],
        [0, 9, 10, 11, 12],
        [0, 13, 14, 15, 16],
        [0, 17, 18, 19, 20],
        [5, 9, 13, 17],
    ]
    for chain in chains:
        for first, second in zip(chain, chain[1:]):
            x1, y1 = converted[first]
            x2, y2 = converted[second]
            drawing.add(Line(x1, y1, x2, y2, strokeColor=BLUE, strokeWidth=1.2))
    for number, (x, y) in converted.items():
        drawing.add(Circle(x, y, 3.8, fillColor=CYAN, strokeColor=BLUE_DARK, strokeWidth=0.7))
        drawing.add(String(x + 5, y - 2.5, str(number), fontName="Helvetica-Bold", fontSize=6.5, fillColor=INK))
    drawing.add(String(300, 205, "21-point hand landmark index", fontName="Helvetica-Bold", fontSize=11, fillColor=BLUE_DARK))
    drawing.add(String(300, 185, "0 wrist", fontName="Helvetica", fontSize=8, fillColor=INK))
    drawing.add(String(300, 170, "1-4 thumb", fontName="Helvetica", fontSize=8, fillColor=INK))
    drawing.add(String(300, 155, "5-8 index", fontName="Helvetica", fontSize=8, fillColor=INK))
    drawing.add(String(300, 140, "9-12 middle", fontName="Helvetica", fontSize=8, fillColor=INK))
    drawing.add(String(300, 125, "13-16 ring", fontName="Helvetica", fontSize=8, fillColor=INK))
    drawing.add(String(300, 110, "17-20 pinky", fontName="Helvetica", fontSize=8, fillColor=INK))
    drawing.add(String(300, 82, "Image x: left -> right", fontName="Helvetica", fontSize=7.5, fillColor=MID))
    drawing.add(String(300, 67, "Image y: top -> bottom", fontName="Helvetica", fontSize=7.5, fillColor=MID))
    drawing.add(String(300, 52, "z: model-relative depth", fontName="Helvetica", fontSize=7.5, fillColor=MID))
    drawing.add(String(300, 27, "This diagram is an index map,", fontName="Helvetica-Oblique", fontSize=7, fillColor=RED))
    drawing.add(String(300, 15, "not a detector output.", fontName="Helvetica-Oblique", fontSize=7, fillColor=RED))
    return drawing


class ProjectDocTemplate(BaseDocTemplate):
    def __init__(self, filename: str, styles):
        super().__init__(
            filename,
            pagesize=A4,
            leftMargin=21 * mm,
            rightMargin=21 * mm,
            topMargin=19 * mm,
            bottomMargin=18 * mm,
            title="Smart Stand Control - Complete Source-Accurate Technical Reference",
            author="Generated from the gesture_detector repository",
            subject="Architecture, gesture logic, thresholds, limitations, validation, and source manifest",
        )
        self.styles = styles
        frame = Frame(
            self.leftMargin,
            self.bottomMargin,
            self.width,
            self.height,
            id="normal",
            leftPadding=0,
            rightPadding=0,
            topPadding=0,
            bottomPadding=0,
        )
        self.addPageTemplates([PageTemplate(id="main", frames=[frame], onPage=self._draw_page)])

    def _draw_page(self, canvas, doc) -> None:
        canvas.saveState()
        canvas.setFillColor(PAPER)
        canvas.rect(0, 0, A4[0], A4[1], fill=1, stroke=0)
        if doc.page > 1:
            canvas.setStrokeColor(GRID)
            canvas.line(doc.leftMargin, A4[1] - 13 * mm, A4[0] - doc.rightMargin, A4[1] - 13 * mm)
            canvas.setFont("Helvetica", 7.5)
            canvas.setFillColor(MID)
            canvas.drawString(doc.leftMargin, A4[1] - 10.5 * mm, "SMART STAND CONTROL - SOURCE REFERENCE")
            canvas.drawRightString(A4[0] - doc.rightMargin, 9.5 * mm, f"Page {doc.page}")
            canvas.drawString(doc.leftMargin, 9.5 * mm, "Snapshot: current working tree, 2026-07-23")
        canvas.restoreState()

    def afterFlowable(self, flowable) -> None:
        if not isinstance(flowable, Paragraph):
            return
        style_name = flowable.style.name
        if style_name not in {"Heading1", "Heading2"}:
            return
        level = 0 if style_name == "Heading1" else 1
        text = flowable.getPlainText()
        key = "section-" + hashlib.sha1(f"{level}:{text}".encode("utf-8")).hexdigest()[:16]
        self.canv.bookmarkPage(key)
        self.canv.addOutlineEntry(text, key, level=level, closed=False)
        self.notify("TOCEntry", (level, text, self.page, key))


def build_styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "CoverTitle": ParagraphStyle(
            "CoverTitle",
            parent=base["Title"],
            fontName="Helvetica-Bold",
            fontSize=27,
            leading=31,
            alignment=TA_LEFT,
            textColor=colors.white,
            spaceAfter=9,
        ),
        "CoverSubtitle": ParagraphStyle(
            "CoverSubtitle",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=12,
            leading=17,
            alignment=TA_LEFT,
            textColor=colors.HexColor("#D8F3F1"),
        ),
        "Heading1": ParagraphStyle(
            "Heading1",
            parent=base["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=18,
            leading=22,
            textColor=BLUE_DARK,
            spaceBefore=7,
            spaceAfter=7,
            keepWithNext=True,
        ),
        "Heading2": ParagraphStyle(
            "Heading2",
            parent=base["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=13.2,
            leading=16,
            textColor=BLUE,
            spaceBefore=8,
            spaceAfter=5,
            keepWithNext=True,
        ),
        "Heading3": ParagraphStyle(
            "Heading3",
            parent=base["Heading3"],
            fontName="Helvetica-Bold",
            fontSize=10.4,
            leading=13,
            textColor=INK,
            spaceBefore=6,
            spaceAfter=3,
            keepWithNext=True,
        ),
        "Lead": ParagraphStyle(
            "Lead",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=10.6,
            leading=15,
            textColor=INK,
            spaceAfter=7,
        ),
        "Body": ParagraphStyle(
            "Body",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=9.2,
            leading=12.5,
            textColor=INK,
            spaceAfter=5,
        ),
        "BodySmall": ParagraphStyle(
            "BodySmall",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=8.1,
            leading=10.7,
            textColor=INK,
        ),
        "BodyTiny": ParagraphStyle(
            "BodyTiny",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=7.1,
            leading=9.0,
            textColor=INK,
        ),
        "Source": ParagraphStyle(
            "Source",
            parent=base["BodyText"],
            fontName="Helvetica-Oblique",
            fontSize=6.7,
            leading=8.5,
            textColor=MID,
            spaceBefore=3,
            spaceAfter=5,
        ),
        "Caption": ParagraphStyle(
            "Caption",
            parent=base["BodyText"],
            fontName="Helvetica-Oblique",
            fontSize=6.7,
            leading=8.4,
            alignment=TA_CENTER,
            textColor=MID,
        ),
        "FieldLabel": ParagraphStyle(
            "FieldLabel",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=8.0,
            leading=10.4,
            textColor=BLUE_DARK,
        ),
        "TableHead": ParagraphStyle(
            "TableHead",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=7.3,
            leading=9,
            textColor=colors.white,
        ),
        "TableCell": ParagraphStyle(
            "TableCell",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=7.2,
            leading=9.1,
            textColor=INK,
        ),
        "TableTiny": ParagraphStyle(
            "TableTiny",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=6.1,
            leading=7.4,
            textColor=INK,
        ),
        "CalloutTitle": ParagraphStyle(
            "CalloutTitle",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=9.2,
            leading=11,
            textColor=BLUE_DARK,
            spaceAfter=3,
        ),
        "TOCHeading": ParagraphStyle(
            "TOCHeading",
            parent=base["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=18,
            leading=22,
            textColor=BLUE_DARK,
            spaceAfter=10,
        ),
    }


@dataclass(frozen=True)
class GestureSpec:
    number: int
    name: str
    action: str
    image: str
    image_note: str
    how_to_pose: list[str]
    exact_logic: list[str]
    timing: str
    priority: str
    actual_effect: str
    limitations: list[str]
    sources: list[str]


GESTURES = [
    GestureSpec(
        1,
        "Move Left",
        "Recognizes a static index-pointing-left pose and displays 'Moving left'.",
        "pointing_index.jpg",
        "Real hand pose family reference. The app mirrors coordinates so left/right follow the visible preview.",
        [
            "Keep the hand steady; extend the index finger toward visible-screen left.",
            "Keep at least one of middle, ring, or pinky folded, or fit the compact palm-circle alternative.",
            "Do not use a victory sign or a closed pinch.",
        ],
        [
            "Reliable hand: score >= 0.45 with landmarks. Hand-center movement must stay <= 0.03 hand-size for 3 frames.",
            "Index points 5-6-7-8 define direction. Both 5-6-7 and 6-7-8 joint angles must be >= 145 degrees.",
            "MCP-to-tip direct distance / full 5-6-7-8 path must be >= 0.80.",
            "Direction angle must be 125..235 degrees after preview mirroring.",
            "Index tip must be left of palm center by 0.10..0.15 palm widths; the exact ratio increases when the tip is deeper behind the palm.",
            "Needs 3 consecutive positive frames after the steady-hand gate.",
        ],
        "Frame based: minimum processing interval 50 ms; no time-based swipe window.",
        "Direction family runs after follow, return-main/call, recording, and custom-overlap blocks. It runs before zoom, but it yields to an armed zoom opening transition.",
        "UI label only. No motor, Bluetooth, network, or serial stand command exists in the repository.",
        [
            "README wording about a swipe/open-hand movement is not the current implementation.",
            "Fast motion fails the steady-hand gate. Occluded folded fingers can make the pose unavailable.",
            "Only the visible static pose is recognized; distance moved over time is not measured.",
        ],
        ["direction_gesture_detector.dart", "hand_gesture_thresholds.dart", "gesture_processing.dart"],
    ),
    GestureSpec(
        2,
        "Move Right",
        "Recognizes a static index-pointing-right pose and displays 'Moving right'.",
        "pointing_index.jpg",
        "Real hand pose family reference. The photograph points left; direction is determined from live landmark geometry.",
        [
            "Keep the hand steady and extend the index finger toward visible-screen right.",
            "Fold at least one of middle, ring, or pinky, or satisfy the compact palm-circle alternative.",
            "Keep thumb and index clearly separated; a closed pinch is reserved for zoom-out.",
        ],
        [
            "Reliable-hand and 3-frame steadiness gates match Move Left.",
            "Index straightness must be >= 0.80. Unlike left, the code does not separately require the two 145-degree index joint checks.",
            "Direction angle wraps through zero: >= 305 degrees OR <= 70 degrees.",
            "Index tip must be right of palm center by a depth-aware 0.10..0.15 palm widths.",
            "A zoom-out closed-pinch conflict explicitly rejects the right pose.",
            "Needs 3 consecutive positive frames.",
        ],
        "Frame based; 3 steady frames plus 3 confirming frames can overlap only as implemented by the detector state.",
        "Same family arbitration as Move Left.",
        "UI label only; it does not drive physical stand hardware.",
        [
            "Right is intentionally asymmetric with left: no explicit 145-degree two-joint gate in the right branch.",
            "Mirroring errors or an unexpected camera coordinate contract can reverse visible direction.",
            "README swipe wording is outdated.",
        ],
        ["direction_gesture_detector.dart", "hand_geometry_service.dart", "gesture_processing.dart"],
    ),
    GestureSpec(
        3,
        "Move Up",
        "Recognizes a static upward index pose and displays 'Moving up'.",
        "pointing_index.jpg",
        "Real hand pose family reference. Rotate the live pose upward; the PDF photo itself is not a detector output.",
        [
            "Hold points 5, 6, 7, and 8 in strictly rising image order.",
            "Keep index mostly vertical and at least one other long finger folded.",
            "Keep the hand center steady for the initial confirmation.",
        ],
        [
            "5-8 vertical span must be >= 0.15 palm width; horizontal spread must be <= 0.75 times that span.",
            "Joint 5-6-7 must be >= 135 degrees and 6-7-8 must be >= 170 degrees.",
            "Initial direction sector is 75..120 degrees; while active it widens to 70..125 degrees.",
            "At least one of middle/ring/pinky must be folded, unless the compact palm circle succeeds.",
            "No extra up-only positive-frame counter exists after the shared 3-frame hand-steadiness gate.",
            "A reliable package Pointing Up label can immediately choose up once the hand is steady.",
        ],
        "Static pose; minimum camera processing interval 50 ms.",
        "Victory package label is rejected before direction. Follow, custom overlaps, recording, punch, and zoom-transition reservations block direction.",
        "UI label only; no stand elevation command is sent.",
        [
            "The source does not track an upward swipe trajectory.",
            "Because package Pointing Up can select up, package model behavior can differ from geometry-only behavior.",
            "A nearly vertical but slightly reversed landmark chain is rejected.",
        ],
        ["direction_gesture_detector.dart", "hand_detection gesture classifier", "gesture_processing.dart"],
    ),
    GestureSpec(
        4,
        "Move Down",
        "Recognizes a static downward index pose and displays 'Moving down'.",
        "pointing_index.jpg",
        "Real hand pose family reference. Use the same one-index shape with the live finger pointing downward.",
        [
            "Hold index PIP, DIP, and tip (6-7-8) in strictly descending image order.",
            "Keep the PIP-to-tip ray mostly vertical and at least one other long finger folded.",
            "Hold the pose steady until confirmation completes.",
        ],
        [
            "6-8 span must be >= 0.15 palm width; horizontal spread <= 0.75 times vertical span.",
            "Joint 6-7-8 must be >= 170 degrees.",
            "Initial sector is 245..295 degrees; active sector is 235..305 degrees.",
            "At least one folded middle/ring/pinky or the compact palm-circle alternative is required.",
            "Needs 3 consecutive positive down frames after steadiness.",
            "The hidden training collector validates downward palm-center travel separately; it is not used by live Move Down recognition.",
        ],
        "3 positive frames, with frames processed no faster than every 50 ms.",
        "Same direction arbitration as the other three directions.",
        "UI label only; no motor command is implemented.",
        [
            "Live recognition is not the two-second temporal training logic.",
            "README describes pointing or moving the palm; implementation uses the index chain.",
            "Down is the only vertical direction with a dedicated 3-positive-frame counter.",
        ],
        ["direction_gesture_detector.dart", "moving_down_capture_contract.dart", "gesture_processing.dart"],
    ),
    GestureSpec(
        5,
        "Detect My Face",
        "Holds a call-me pose for 2 seconds, runs face detection, and selects a face box.",
        "call_me.png",
        "Real Shaka/call-me hand. The live code evaluates landmark ratios, not image templates.",
        [
            "Extend thumb and pinky while folding index, middle, and ring.",
            "Keep thumb and pinky separated and hold continuously for 2 seconds.",
            "Use only when no follow-target identity is already remembered.",
        ],
        [
            "Thumb tip distance from 3D palm center must exceed thumb-IP distance * 1.15 and hand-size * 0.23.",
            "Pinky tip must exceed PIP distance * 1.20 and hand-size * 0.30.",
            "Each folded index/middle/ring passes if tip <= PIP distance * 1.03 OR tip < hand-size * 0.26.",
            "Thumb-tip to pinky-tip 3D distance must exceed hand-size * 0.55.",
            "After 2 continuous seconds, the fast ML Kit face detector returns candidates and the presentation layer selects the best face target.",
        ],
        "2-second continuous hold; losing the pose clears the hold.",
        "Runs before follow-object, recording, direction, and zoom when no remembered target identity blocks it.",
        "Locks and follows a face bounding box and updates camera focus/exposure. It does not identify a person.",
        [
            "This is face detection, not face recognition, authentication, or identity verification.",
            "A detected face can be missed under profile pose, obstruction, poor light, or scale limits.",
            "The repository contains no consent, biometric storage, or identity database flow.",
        ],
        ["custom_gesture_detector.dart", "gesture_processing.dart", "google_mlkit_face_detection"],
    ),
    GestureSpec(
        6,
        "Follow The Object",
        "Runs open-palm hold -> closed fist -> final open/relaxed release, then selects and tracks a face or non-person object.",
        "open_palm_hand.jpg",
        "Real open palm used for the first and final phase. Closed-fist phase is shown in the tracking chapter.",
        [
            "Hold an open palm for 1 second.",
            "Show the package-classified closed fist. Full-screen face/object candidate scanning then becomes active.",
            "Move the hand over the target and release with an open palm or at least one relaxed extended long finger for 2 frames.",
        ],
        [
            "Custom open-palm confidence uses enter 0.55 / exit 0.45 hysteresis, 4 samples, >= 2 positive samples, max age 500 ms.",
            "Closed fist comes from the 8-class package classifier at confidence >= 0.50; a compact Punch-circle match is excluded.",
            "Release point is the center of the hand bounding box, not index point 8.",
            "Candidate memory requires 2 compatible fresh detection cycles and tolerates <= 0.15 normalized hand movement for 2 seconds.",
            "Selection prefers the smallest box containing a point padded by 0.10; the live release path also supports the nearest fresh candidate.",
            "If the hand disappears after fist, a 2-second grace period allows return; timeout auto-releases from the last visible hand center.",
        ],
        "1-second first palm; 2-frame relaxed release; 2-second lost-hand grace; result message 1.2 seconds.",
        "While active it suppresses custom actions, recording, direction, and zoom. Follow state is the highest long-running activity.",
        "Selects a box, maintains a target identity record, smooths/predicts the box, and updates camera focus/exposure. It does not move a physical stand.",
        [
            "Object identity is heuristic: tracking ID when available, else type/label/class/spatial continuity and a compact appearance signature.",
            "Occlusion, similar adjacent objects, detector latency, stale held results, and lighting changes can switch or lose a target.",
            "All object backends remove the 'person' class; people are represented only by face boxes.",
        ],
        ["follow_object_sequence_detector.dart", "open_palm_gesture_detector.dart", "follow_target_selector.dart", "gesture_processing.dart"],
    ),
    GestureSpec(
        7,
        "Stop and Continue Action",
        "Displays 'Stop & Continue Action' for a reliable package Thumb Up label.",
        "thumbs_up.jpg",
        "Real thumbs-up reference. Recognition comes from the package classifier, not repo-defined angles.",
        ["Show a thumbs-up pose that the package classifier recognizes.", "Keep the hand detection score and package confidence above their gates."],
        [
            "Hand score must be >= 0.45 and package Thumb Up confidence >= 0.50.",
            "The vendored recognizer maps 63 image landmark values + handedness + 63 world values into a 128-D embedding and 8-class classifier.",
            "No local thumbs-up angles, no 1-second timer, and no stop/continue toggle state exist.",
        ],
        "No hold timer in current code, despite README saying 1 second.",
        "Package labels are considered after higher-priority follow/custom/record/direction/zoom decisions.",
        "Text feedback only. There is no stop/continue side effect or stand-control command.",
        [
            "The feature name overstates implemented behavior.",
            "Classifier weights and training data are opaque model assets, so exact pose boundaries are not derivable from source.",
            "README timing is inaccurate for the current working tree.",
        ],
        ["gesture_processing.dart", "hand_gesture_label_mapper.dart", "third_party/hand_detection/gesture_recognizer.dart"],
    ),
    GestureSpec(
        8,
        "Return To Main Position",
        "Holds all four long fingers pointing down for 1 second, then clears active gesture tasks and resets camera zoom/focus.",
        "open_palm_hand.jpg",
        "Real open-hand reference. For the live gesture all four long-finger chains must point downward.",
        [
            "Point index, middle, ring, and pinky downward together.",
            "Keep each MCP->PIP->DIP->TIP chain descending with visible separation.",
            "Hold continuously for 1 second.",
        ],
        [
            "Each long finger needs MCP-PIP-TIP 3D joint angle >= 135 degrees.",
            "Each MCP-to-tip projected distance must be >= 0.20 hand-size.",
            "Every adjacent MCP->PIP->DIP->TIP y-step must descend by >= 0.04 hand-size.",
            "After 1 second, the detector holds the result for 900 ms to avoid flicker.",
            "The live screen clears zoom/direction/follow/record gesture state, target identity/candidates, and optionally resets camera zoom/focus.",
        ],
        "1-second pose hold; 900 ms result latch.",
        "Return-main is evaluated before face, follow, recording, direction, zoom, and package labels.",
        "Resets in-app camera and gesture state. It does not physically return a stand to a mechanical home position.",
        [
            "README's circular index-finger description is obsolete and contradicts current source.",
            "All four finger chains must remain visible; partial occlusion breaks the hold.",
            "No hardware homing protocol exists in this repository.",
        ],
        ["custom_gesture_detector.dart", "hand_gesture_thresholds.dart", "gesture_processing.dart"],
    ),
    GestureSpec(
        9,
        "Start Record Video",
        "Holds a geometry-defined OK sign for 1 second and starts camera video recording.",
        "ok.jpg",
        "Real OK gesture reference. Exact acceptance uses 3D landmark distances and angles.",
        ["Touch thumb tip to index tip, bend index, and extend middle/ring/pinky.", "Hold for 1 second while not already recording."],
        [
            "Thumb-index weighted 3D distance <= max(hand-size * 0.11, 12 pixels).",
            "Index MCP-PIP-tip 3D angle <= 150 degrees.",
            "Middle/ring/pinky must each pass angle-based 3D extension geometry.",
            "At 1 second the stream switches to startVideoRecording(onAvailable: _processCameraImage), with orientation locking and transition overlays.",
            "The camera controller is created with enableAudio: false, so recordings are silent.",
        ],
        "1-second continuous hold; triggers once until the pose changes.",
        "Recording gestures are disabled during follow. Start requires no conflicting custom overlap.",
        "Starts a silent camera recording and an elapsed timer.",
        [
            "No audio is recorded even though iOS includes a microphone usage description.",
            "The fixed 12-pixel floor makes the OK touch rule partly scale-dependent.",
            "Camera-plugin recording support varies by device; start errors only show a snackbar and resume streaming best-effort.",
        ],
        ["custom_gesture_detector.dart", "recording_controls.dart", "camera_lifecycle.dart"],
    ),
    GestureSpec(
        10,
        "Pause or Resume Video",
        "Holds the custom compact Punch-circle pose for 1 second to toggle recording pause/resume.",
        "closed_fist.jpg",
        "Real closed fist reference. The code calls this recording pose 'Punch' and uses an all-landmarks circle, not the package fist label.",
        ["While recording, compact the complete hand so every landmark fits the defined circle.", "Hold for 1 second; repeat after changing pose to toggle again."],
        [
            "Circle center is midpoint of middle MCP/PIP (9/10), or point 10 if point 9 is missing.",
            "Radius = max(0.30 * hand-size, distance between index MCP 5 and ring MCP 13).",
            "All 21 landmarks must be visible and inside; wrist point 0 must be inside.",
            "Normal preview Punch requires 3 steady frames at <= 0.03 hand-size center movement, but recording uses raw one-frame match plus the 1-second hold.",
            "The action calls pauseVideoRecording or resumeVideoRecording and pauses/resumes the app timer.",
        ],
        "1-second continuous hold; only valid while recording.",
        "Recording action wins over direction and zoom, but follow blocks it.",
        "Toggles the current silent video recording between paused and active.",
        [
            "README says fist, but package Closed Fist is not the recording gate; exact compact-circle geometry is.",
            "Requiring all 21 reliable landmarks makes the pose sensitive to self-occlusion.",
            "Pause/resume capability depends on the camera plugin and platform implementation.",
        ],
        ["custom_gesture_detector.dart", "hand_geometry_service.dart", "recording_controls.dart"],
    ),
    GestureSpec(
        11,
        "End Record Video",
        "Holds a reliable package Victory sign for 2 seconds and stops the recording.",
        "victory.jpg",
        "Real victory/peace gesture reference. Classification comes from the vendored model.",
        ["While recording, show a victory sign and keep it continuously recognized for 2 seconds."],
        [
            "Hand score >= 0.45 and package Victory confidence >= 0.50.",
            "After 2 seconds, stopVideoRecording returns an XFile; Android then attempts a copy to /storage/emulated/0/Download.",
            "Android filename: smart_stand_recording_<ISO timestamp with ':' and '.' replaced by '-'> plus source extension, default .mp4.",
            "The normal image stream restarts after stop and a short 300 ms transition hold.",
        ],
        "2-second continuous hold; triggers once per unchanged pose.",
        "Victory blocks direction. The stop mapping only exists while recording; otherwise the UI can show 'Victory'.",
        "Stops the video and reports it as saved.",
        [
            "On non-Android, _copyRecordingToDownloads returns the original XFile, yet the UI still says 'saved to Download folder'. That message is inaccurate on iOS.",
            "Android copy failures are caught and return the original camera file; the success snackbar can still be misleading.",
            "No gallery/media-library insertion is implemented for recordings.",
        ],
        ["recording_controls.dart", "gesture_processing.dart", "camera_lifecycle.dart"],
    ),
    GestureSpec(
        12,
        "Zoom In",
        "Recognizes a stable thumb-index separated pose for 1 second, or immediately continues an armed zoom-out-to-open transition, then adds 0.20 camera zoom.",
        "ok.jpg",
        "Real thumb-index pose family reference. For Zoom In the tips must be clearly separated, not touching as in this photograph.",
        [
            "Fold middle, ring, and pinky; face the palm side toward the camera.",
            "Place index segment above thumb segment and separate thumb/index tips to >= 0.22 hand-size in both 2D and weighted 3D.",
            "Hold the palm and at least two folded fingertips stable for 1 second, or open after a completed Zoom Out.",
        ],
        [
            "Middle/ring/pinky must be folded by 3D angle. Required landmark visibility is 0.30.",
            "Palm-side normalized cross >= 0.10; index segment above thumb by >= 0.02 hand-size.",
            "Thumb/index forward rays must intersect in the handedness-aware screen quadrant, or be parallel within 5 degrees with line separation >= 0.10 hand-size.",
            "Palm movement <= 0.08 hand-size; at least 2 of middle/ring/pinky tips move <= 0.07 hand-size relative to palm.",
            "Static hold is 1 second. Each application changes camera zoom by +0.20 and repeat interval is >= 1 second.",
        ],
        "1-second static hold, except immediate output in the active opening transition; repeat no faster than 1 second.",
        "Zoom runs only when follow/custom overlap/recording/direction/blocking package/manual zoom are absent. An armed opening transition blocks direction.",
        "Changes camera zoom level, clamped to device min/max.",
        [
            "The real-image card is only a pose-family cue; exact Zoom In is not the photographed OK sign.",
            "Depth noise, incorrect palm-side orientation, or nearly parallel rays in the wrong quadrant rejects the pose.",
            "A 0.20 level step is not a constant field-of-view percentage across devices.",
        ],
        ["zoom_gesture_detector.dart", "zoom_controls.dart", "hand_geometry_service.dart"],
    ),
    GestureSpec(
        13,
        "Zoom Out",
        "Recognizes a stable closed thumb-index pinch for 1 second and subtracts 0.20 camera zoom; completion arms the opening path for Zoom In.",
        "ok.jpg",
        "Real tip-contact reference. Middle, ring, and pinky must be folded in the live Zoom Out pose.",
        [
            "Fold middle/ring/pinky, face the palm side to camera, keep index segment above thumb, and touch thumb/index tips.",
            "Hold palm and folded fingertips stable for 1 second.",
        ],
        [
            "Closed if 2D tip gap <= 0.08 hand-size OR weighted 3D tip gap <= 0.18 hand-size.",
            "A tucked thumb that belongs to a fist/index-point pose rejects the pinch when the tuck check returns false for zoom eligibility.",
            "The same palm-side, visibility, index-above-thumb, and stability gates as Zoom In apply.",
            "After the one-second match, zoom changes by -0.20 and the opening transition becomes armed.",
            "The neutral gap between closed 0.18 and clearly open 0.22 avoids immediate ambiguous static classification.",
        ],
        "1-second static hold; repeat no faster than 1 second.",
        "Same zoom arbitration. Right-direction logic also explicitly rejects a zoom-out conflict.",
        "Changes camera zoom level, clamped at the device minimum.",
        [
            "2D contact can override noisy depth, so perspective overlap may produce a false pinch.",
            "All three other fingers must pass folded-angle checks.",
            "The gesture changes only camera zoom; it has no mechanical stand effect.",
        ],
        ["zoom_gesture_detector.dart", "hand_gesture_thresholds.dart", "zoom_controls.dart"],
    ),
]


def run_text(command: list[str]) -> str:
    try:
        return subprocess.check_output(command, cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unavailable"


def git_snapshot() -> dict[str, str]:
    status = run_text(["git", "status", "--short"])
    return {
        "branch": run_text(["git", "branch", "--show-current"]),
        "head": run_text(["git", "rev-parse", "--short=12", "HEAD"]),
        "status": "clean" if not status else "dirty - current uncommitted working tree documented",
        "changed_count": "0" if not status else str(len(status.splitlines())),
    }


def parse_static_constants() -> list[tuple[str, str, str]]:
    lines = THRESHOLD_FILE.read_text(encoding="utf-8").splitlines()
    declarations: list[str] = []
    active: list[str] = []
    for raw in lines:
        stripped = raw.strip()
        if not active and "static const" not in stripped:
            continue
        if not active:
            active = [stripped]
        else:
            active.append(stripped)
        if ";" in stripped:
            declaration = " ".join(active)
            declaration = re.sub(r"\s+", " ", declaration)
            declarations.append(declaration)
            active = []

    parsed: list[tuple[str, str, str]] = []
    pattern = re.compile(
        r"static const\s+(.+?)\s+([A-Za-z_]\w*)\s*=\s*(.*?)\s*;\s*$"
    )
    for declaration in declarations:
        match = pattern.search(declaration)
        if not match:
            parsed.append(("unparsed", declaration, "See source"))
            continue
        type_name, name, value = match.groups()
        parsed.append((type_name, name, value))
    return parsed


MANIFEST_EXTENSIONS = {
    ".dart", ".java", ".kt", ".kts", ".swift", ".m", ".mm", ".h",
    ".xml", ".gradle", ".yaml", ".yml", ".json", ".md", ".properties",
    ".plist", ".xcconfig", ".toml",
}


def source_manifest() -> list[tuple[str, int, str]]:
    output = run_text(["git", "ls-files", "-co", "--exclude-standard"])
    rows: list[tuple[str, int, str]] = []
    if output == "unavailable":
        return rows
    for raw_path in sorted(set(output.splitlines())):
        if not raw_path or raw_path.startswith(("tmp/", "output/", ".dart_tool/", "build/")):
            continue
        path = ROOT / raw_path
        if not path.is_file() or path.suffix.lower() not in MANIFEST_EXTENSIONS:
            continue
        payload = path.read_bytes()
        try:
            line_count = len(payload.decode("utf-8").splitlines())
        except UnicodeDecodeError:
            line_count = 0
        digest = hashlib.sha256(payload).hexdigest()[:12]
        rows.append((raw_path, line_count, digest))
    return rows


def add_heading(story: list[Flowable], text: str, styles, level: int = 1) -> None:
    story.append(para(text, styles[f"Heading{level}"]))


def cover_story(styles, snapshot: dict[str, str]) -> list[Flowable]:
    cover_body = [
        para("SMART STAND CONTROL", styles["CoverSubtitle"]),
        Spacer(1, 6 * mm),
        para("Complete Source-Accurate Project Reference", styles["CoverTitle"]),
        Spacer(1, 3 * mm),
        para(
            "Architecture, every gesture family, camera and coordinate logic, face/object following, recording, zoom, training export, platform behavior, exact thresholds, known limitations, test evidence, and source manifest.",
            styles["CoverSubtitle"],
        ),
        Spacer(1, 10 * mm),
        data_table(
            [
                ["Snapshot", "Value"],
                ["Generated", "2026-07-23 (Asia/Dhaka)"],
                ["Branch", snapshot["branch"]],
                ["Git HEAD", snapshot["head"]],
                ["Working tree", snapshot["status"]],
                ["Pinned Flutter", "3.41.7 via .fvmrc"],
                ["App version", "1.0.0+1"],
            ],
            styles,
            widths=[43 * mm, 105 * mm],
        ),
    ]
    cover = Table([[cover_body]], colWidths=[167 * mm], rowHeights=[225 * mm])
    cover.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), BLUE_DARK),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 13 * mm),
                ("RIGHTPADDING", (0, 0), (-1, -1), 13 * mm),
                ("TOPPADDING", (0, 0), (-1, -1), 18 * mm),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 12 * mm),
            ]
        )
    )
    return [cover, Spacer(1, 5 * mm), para("Prepared directly from the current repository source. Real-hand photographs are credited in Appendix C.", styles["Caption"]), PageBreak()]


def document_contract_story(styles) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "How to read this reference", styles)
    story.append(
        callout(
            "Accuracy boundary",
            "This document is source-accurate for the current working tree at the snapshot above. It does not claim that a probabilistic ML model will recognize every real hand, that every phone camera behaves identically, or that opaque model weights can be explained from source. Every empirical limitation is separated from deterministic code behavior.",
            styles,
            BLUE,
        )
    )
    story.append(Spacer(1, 4 * mm))
    story.append(
        data_table(
            [
                ["Evidence label", "Meaning"],
                ["Source-proven", "Directly read from Dart, Java/Kotlin/Swift, configuration, or tests in this working tree."],
                ["Model-dependent", "Controlled by TFLite, ML Kit, EfficientDet, YOLO, or device camera internals; source defines inputs/gates but not every learned boundary."],
                ["Device-dependent", "Varies with lens, sensor orientation, zoom range, camera plugin support, GPU/CPU delegates, storage policy, and OS."],
                ["Illustration", "Real-hand photographs show pose families only. They are not labeled inference outputs and do not replace exact landmark rules."],
            ],
            styles,
            widths=[35 * mm, 132 * mm],
        )
    )
    story.append(Spacer(1, 5 * mm))
    story.append(
        callout(
            "Most important project truth",
            "The app detects and displays gestures, changes camera zoom, records silent video, selects visual face/object targets, and updates camera focus/exposure. The repository contains no Bluetooth, serial, network, motor, or stand-controller integration. Therefore Move Left/Right/Up/Down, Stop & Continue, Follow, and Return Main do not physically move a stand.",
            styles,
            RED,
        )
    )
    story.append(PageBreak())
    return story


def toc_story(styles) -> list[Flowable]:
    toc = TableOfContents()
    toc.levelStyles = [
        ParagraphStyle(
            name="TOCLevel1",
            fontName="Helvetica-Bold",
            fontSize=9.2,
            leading=13,
            leftIndent=0,
            firstLineIndent=0,
            textColor=BLUE_DARK,
            spaceBefore=3,
        ),
        ParagraphStyle(
            name="TOCLevel2",
            fontName="Helvetica",
            fontSize=7.8,
            leading=10.4,
            leftIndent=12,
            firstLineIndent=0,
            textColor=INK,
        ),
    ]
    return [para("Table of contents", styles["TOCHeading"]), toc, PageBreak()]


def overview_story(styles, manifest: list[tuple[str, int, str]]) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "1. Project purpose and architecture", styles)
    story.append(
        para(
            "Smart Stand Control is a Flutter camera application whose primary implemented mode is Hand Gesture. It combines a vendored two-stage hand detector, custom deterministic hand geometry, a canned gesture classifier, ML Kit face detection, one selectable object detector backend, camera recording/zoom, target tracking, and a root point-8 dwell cursor.",
            styles["Lead"],
        )
    )
    story.append(PipelineDiagram())
    story.append(Spacer(1, 4 * mm))
    source_lines = sum(lines for _, lines, _ in manifest)
    lib_files = sum(1 for path, _, _ in manifest if path.startswith("lib/"))
    test_files = sum(1 for path, _, _ in manifest if path.startswith("test/"))
    story.append(
        key_value_table(
            [
                ("App entry", "lib/main.dart"),
                ("Default mode", "Hand Gesture"),
                ("Visible debug entry", "Face/Object Debug floating button is enabled"),
                ("Hidden entry", "Moving Down training list item is disabled by a main.dart constant"),
                ("Home pointer", "Enabled; hidden front camera on home, or external live-screen landmarks"),
                ("Source inventory", f"{len(manifest)} tracked/untracked text source/config files, {source_lines:,} lines; {lib_files} lib files and {test_files} test files"),
            ],
            styles,
        )
    )
    add_heading(story, "1.1 Runtime screen flow", styles, 2)
    story.append(
        numbered_list(
            [
                "main() initializes Flutter, loads the persisted object backend, renders GestureDetectorApp, then starts a non-awaited Ultralytics model prefetch on Android/iOS.",
                "The home page offers Automatic Detect, Hand Gesture, and Voice Command. Automatic and Voice only show 'coming soon'.",
                "Hand Gesture suspends the hidden home camera, opens AdminHandGestureLiveScreen with the front lens, then resumes the home camera after navigation returns.",
                "The debug floating button opens FaceObjectDebugCameraScreen with the selected object backend and front lens.",
                "The optional Moving Down page records a two-second raw landmark sample and exports JSONL after review.",
            ],
            styles,
        )
    )
    source_line(["lib/main.dart", "lib/hand_gesture_features/stand_control_home_page.dart", "settings_panel.dart"], styles)
    add_heading(story, "1.2 Major code ownership", styles, 2)
    story.append(
        data_table(
            [
                ["Area", "Primary files", "Responsibility"],
                ["App/home", "main.dart; stand_control_home_page.dart; settings_panel.dart", "Mode selection, detector preference, navigation, root pointer overlay."],
                ["Hand pipeline", "hand_detector_factory.dart; third_party/hand_detection", "Palm box, 21 landmarks, handedness, world landmarks, canned gestures, ROI tracking."],
                ["Gesture domain", "custom_gesture_detector.dart; direction_gesture_detector.dart; zoom_gesture_detector.dart; open_palm_gesture_detector.dart", "Deterministic landmark geometry and temporal state."],
                ["Live orchestration", "admin_hand_gesture_live_screen.dart plus five part files", "Camera lifecycle, frame loop, priority, recording, zoom, overlays."],
                ["Follow", "follow_object_sequence_detector.dart; follow_target_selector.dart; target smoother; object_optical_flow_tracker.dart", "Sequence, selection, identity, tracking, focus/exposure."],
                ["Object ML", "five ObjectDetectionService implementations; two Android plugins", "Backend-specific preprocessing, inference, validation, common app detections."],
                ["Training", "moving_down_capture_screen.dart; moving_down_capture_contract.dart; MainActivity.java", "Two-second capture, 35-field v2 JSONL review/validation/storage."],
            ],
            styles,
            widths=[27 * mm, 65 * mm, 75 * mm],
        )
    )
    story.append(PageBreak())
    return story


def camera_hand_story(styles) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "2. Camera, coordinates, and hand inference", styles)
    add_heading(story, "2.1 Camera ownership and frame cadence", styles, 2)
    story.append(
        data_table(
            [
                ["Screen", "Preset / audio", "Frame format", "Special behavior"],
                ["Home pointer", "medium / false", "iOS BGRA8888; otherwise YUV420", "Front lens preferred; 200/500/1000/2000 ms retries; 2 s watchdog; 5 s stall timeout."],
                ["Hand live", "high / false", "iOS BGRA8888; Android YUV420; other BGRA8888", "Portrait UI/capture lock; front/back switch; camera card can rotate portrait/landscape."],
                ["Face/object debug", "high / false", "Same as hand live", "Displays raw face/object boxes and exports point 8 to root cursor."],
                ["Moving Down", "high / false", "iOS BGRA8888; otherwise YUV420", "Portrait-only two-second collector with review thumbnails."],
            ],
            styles,
            widths=[30 * mm, 31 * mm, 47 * mm, 59 * mm],
        )
    )
    story.append(
        bullet_list(
            [
                "Live gesture processing is single-flight: a new frame is ignored while _isProcessing is true.",
                "Frames are processed no faster than every 50 ms, so the theoretical app-side hand loop ceiling is 20 Hz before inference cost.",
                "Hand input max dimension is 640. Object-tracking grayscale frames are max 480, or 320 on iOS.",
                "Camera rotation is derived from raw dimensions, sensor orientation, lens direction, and locked/device orientation. Mirroring is applied separately so detector space remains unmirrored and preview space matches the user.",
            ],
            styles,
        )
    )
    source_line(["camera_lifecycle.dart", "gesture_processing.dart", "camera_preview_geometry.dart", "home_hand_pointer_layer.dart"], styles)

    add_heading(story, "2.2 Hand detector configuration", styles, 2)
    story.append(
        key_value_table(
            [
                ("Pipeline", "Palm detection box -> rotated/cropped hand ROI -> full 21-landmark model -> handedness/world landmarks -> optional canned gesture recognition"),
                ("App configuration", "boxesAndLandmarks; full model; palm detector confidence 0.60; max detections 1; minimum landmark score 0.60; tracking on; gestures on"),
                ("Interpreter policy", "iOS forces non-compiled XNNPACK path. Other targets try compiled model first and fall back to XNNPACK on initialization failure."),
                ("Tracking defaults", "ROI scale 2.0; shift Y -0.1; association IoU 0.5; normalized ROI size 0.03..1.2"),
                ("Canned classifier", "63 image landmark values + 1 handedness value + 63 world values -> 128-D embedder -> 8 probabilities"),
                ("Classes", "Unknown, Closed Fist, Open Palm, Pointing Up, Thumb Down, Thumb Up, Victory, I Love You"),
                ("Package confidence", "Recognizer minimum 0.50; live app also requires package confidence >= 0.50 and reliable hand score >= 0.45"),
            ],
            styles,
        )
    )
    story.append(
        callout(
            "One-hand limit",
            "Although UI state stores a list of hands, HandDetectorFactory configures maxDetections: 1. All primary gesture decisions use the best reliable hand. Multi-hand interaction is therefore not implemented.",
            styles,
            ORANGE,
        )
    )
    source_line(["hand_detector_factory.dart", "third_party/hand_detection/lib/src/hand_detector.dart", "shared/hand_types.dart", "gesture_recognizer.dart"], styles)

    add_heading(story, "2.3 Landmark coordinate map", styles, 2)
    story.append(landmark_drawing())
    story.append(Spacer(1, 3 * mm))
    landmarks = [
        ["ID", "Name", "High-value uses"],
        ["0", "wrist", "Palm centers/plane; direction circle; return-main and punch wrist gate."],
        ["1-4", "thumb CMC/MCP/IP/tip", "Open palm, call-me, OK touch, zoom rays/pinch, fist/tuck checks."],
        ["5-8", "index MCP/PIP/DIP/tip", "Directions; OK; zoom; root point-8 cursor; target debug dwell."],
        ["9-12", "middle MCP/PIP/DIP/tip", "Palm center, folded/open checks; punch center uses 9/10."],
        ["13-16", "ring MCP/PIP/DIP/tip", "Folded/open checks; punch minimum radius anchor 13."],
        ["17-20", "pinky MCP/PIP/DIP/tip", "Palm plane/width, call-me, open-palm spread, folded/open checks."],
    ]
    story.append(data_table(landmarks, styles, widths=[14 * mm, 40 * mm, 113 * mm]))
    story.append(
        callout(
            "Geometry convention",
            "Most custom 3D checks weight depth differences by 0.65. A landmark is normally considered visible at visibility >= 0.35; zoom uses 0.30. Hand size is the larger absolute side of the detected hand bounding box. Palm center is the average of visible wrist and four MCP knuckles.",
            styles,
        )
    )
    story.append(PageBreak())
    return story


def priority_story(styles) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "3. Gesture arbitration and UI state", styles)
    story.append(
        para(
            "A pose can satisfy several detectors at once. The live screen therefore computes raw custom/package/follow states, builds explicit block reasons, and chooses one user-visible result. Priority is part of correctness, not just presentation.",
            styles["Lead"],
        )
    )
    story.append(
        data_table(
            [
                ["Priority", "Family", "What happens"],
                ["1", "No reliable hand / follow release", "Continue lost-hand grace or clear follow state. A remembered target can still be refreshed separately."],
                ["2", "Return-main and face-detect hold", "Return-main can clear everything. Call-me can start face selection when no identity is remembered."],
                ["3", "Follow-object sequence and target selection", "Open/fist/release sequence owns gesture flow and suppresses other actions."],
                ["4", "Recording", "OK start, raw Punch pause/resume, Victory stop, each with continuous hold state."],
                ["5", "Static one-index directions", "Left/right/up/down geometry runs if follow/custom overlap/record/punch/package/zoom-transition blockers are absent."],
                ["6", "Zoom and remaining package labels", "Zoom applies only after a direction result is absent and all zoom blockers are clear. Remaining package labels are display feedback."],
            ],
            styles,
            widths=[16 * mm, 46 * mm, 105 * mm],
        )
    )
    add_heading(story, "3.1 Raw custom overlap rules", styles, 2)
    story.append(
        bullet_list(
            [
                "CustomGestureDetector can report return-main, OK, call-me, and Punch. Return-main is treated as exclusive cancellation.",
                "A single custom result may drive recording/call behavior. Multiple simultaneous custom matches create an overlap block and stop direction/zoom fallback.",
                "Victory has special precedence over pointing directions. Package Pointing Up may directly produce the up direction once steady.",
                "Punch uses deterministic all-landmark circle geometry. Package Thumb Down is only mapped to the word 'Punch' for display and is not the recording pause gate.",
                "Follow sequence distinguishes package Closed Fist from compact Punch: if Punch geometry matches, Closed Fist is rejected for the sequence phase.",
            ],
            styles,
        )
    )
    add_heading(story, "3.2 Display order", styles, 2)
    story.append(
        para(
            "After detection/action updates, visible text is chosen in this order: locked follow target; follow selection failure; no-target release; follow success; remembered-identity unavailable; following hand; active follow sequence; recording feedback; Punch; single custom gesture; custom overlap; zoom result/candidate/hold; movement; known package gesture; generic hand detected.",
            styles["Body"],
        )
    )
    story.append(
        callout(
            "Action text is not action transport",
            "A status such as 'Moving left', 'Follow the object', or 'Stop & Continue Action' is not evidence of a stand command. There is no command transport layer in pubspec or source.",
            styles,
            RED,
        )
    )
    source_line(["admin_hand_gesture_live_screen_parts/gesture_processing.dart", "custom_gesture_detector.dart", "direction_gesture_detector.dart", "zoom_gesture_detector.dart"], styles)
    story.append(PageBreak())
    return story


def gesture_story(styles) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "4. Complete 13-gesture catalog", styles)
    story.append(
        callout(
            "Photograph rule",
            "The real-hand images below are pose-family references selected from Wikimedia Commons. They are not frames from this app, do not show its landmark confidence, and are never used by the detector. Exact source behavior is in each logic block.",
            styles,
            ORANGE,
        )
    )
    story.append(PageBreak())
    for index, gesture in enumerate(GESTURES):
        add_heading(story, f"4.{gesture.number} {gesture.name}", styles, 2)
        story.append(para(gesture.action, styles["Lead"]))
        photo = image_card(gesture.image, gesture.image_note, styles, width=66 * mm, height=42 * mm)
        pose = Table(
            [[photo, bullet_list(gesture.how_to_pose, styles, compact=True)]],
            colWidths=[72 * mm, 95 * mm],
            rowHeights=[52 * mm],
            hAlign="LEFT",
        )
        pose.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 5)]))
        story.append(pose)
        story.append(Spacer(1, 3 * mm))
        story.append(key_value_table([
            ("Exact source logic", bullet_list(gesture.exact_logic, styles, compact=True)),
            ("Timing", gesture.timing),
            ("Priority", gesture.priority),
            ("Implemented effect", gesture.actual_effect),
            ("Limitations", bullet_list(gesture.limitations, styles, compact=True)),
        ], styles))
        source_line(gesture.sources, styles)
        if index != len(GESTURES) - 1:
            story.append(PageBreak())
    story.append(PageBreak())
    return story


def follow_object_story(styles) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "5. Face/object selection and tracking", styles)
    story.append(
        para(
            "Follow is a layered system: a hand state machine chooses a release point; face/object detectors produce normalized candidates; selection memory confirms one target; identity and spatial gates refresh it; a smoother and frame-to-frame tracker bridge detector gaps; camera focus/exposure follows the target center.",
            styles["Lead"],
        )
    )
    trio = Table(
        [[
            image_card("open_palm_hand.jpg", "1. Open palm for 1 second", styles, 48 * mm, 36 * mm),
            image_card("closed_fist.jpg", "2. Closed fist arms target scan", styles, 48 * mm, 36 * mm),
            image_card("open_palm_hand.jpg", "3. Open or relaxed release", styles, 48 * mm, 36 * mm),
        ]],
        colWidths=[55 * mm, 55 * mm, 55 * mm],
        hAlign="LEFT",
    )
    trio.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 2)]))
    story.append(trio)

    add_heading(story, "5.1 Follow sequence state machine", styles, 2)
    story.append(
        data_table(
            [
                ["Phase", "Entry", "Exit / failure"],
                ["idle", "No active sequence", "Reliable custom open palm starts a one-second hold."],
                ["holding first open", "Open palm remains continuous", "After 1 s -> wait for closed. Interruption resets first hold."],
                ["waiting for closed", "Sequence remains active with hand visible", "Reliable package Closed Fist >= 0.50 -> target selection. Punch-circle fist is excluded."],
                ["waiting for final open", "Detectors scan candidates and remember hand box center", "Custom open palm or >=1 relaxed long finger for 2 frames releases."],
                ["waiting for hand return", "Hand lost after closed fist; saved center exists", "Closed fist can return; release pose completes; 2 s timeout auto-releases saved center."],
                ["recent detected latch", "Release completed", "Displays success for 1.2 s, then returns idle."],
            ],
            styles,
            widths=[33 * mm, 65 * mm, 69 * mm],
        )
    )
    add_heading(story, "5.2 Open-palm scoring", styles, 2)
    story.append(
        bullet_list(
            [
                "The custom detector requires a reliable hand and 21-landmark geometry. It rejects visible landmark overlaps closer than 0.012 hand-size and crossed adjacent finger chains.",
                "Four long-finger extension scores plus thumb, spread, palm-side, image-Y, upper-chain, and adjacent-separation components are combined. Weighted confidence = finger average * 0.60 + spread * 0.15 + palm side * 0.12 + Y * 0.13, then minimum component gates clamp acceptance.",
                "Finger extension score uses angle 145..165 degrees, tip/PIP ratio 1.08..1.22, and reach 0.25..0.34 hand-size. Thumb score uses angle 125..155 plus reach and index separation.",
                "Enter threshold is 0.55 and exit threshold 0.45. Four samples younger than 500 ms are retained and at least two must be positive.",
            ],
            styles,
        )
    )
    source_line(["open_palm_gesture_detector.dart", "follow_object_sequence_detector.dart"], styles)

    add_heading(story, "5.3 Candidate selection and identity", styles, 2)
    story.append(
        data_table(
            [
                ["Stage", "Exact behavior", "Risk"],
                ["Candidate pool", "Fast ML Kit faces plus non-person objects from selected backend. Detections older than 700 ms are not fresh for selection.", "Face and object cycles are asynchronous and can describe different instants."],
                ["Point selection", "Smallest candidate whose box inflated by 0.10 contains the point; nearest-center fallback is used by live release paths.", "Padding can favor a small neighboring box; nearest does not impose a maximum selection distance."],
                ["Memory", "Requires 2 compatible fresh detector cycles; remembered for 2 s while hand moves <= 0.15 normalized distance.", "Ambiguous/missing compatible candidates hide or clear unconfirmed memory."],
                ["Identity", "Tracking ID if both have one. Else same target type and normalized label; objects also require class index. Faces can compare appearance signature.", "Labels/classes are not unique real-world identities."],
                ["Spatial continuity", "IoU >= 0.08 OR normalized center distance <= 0.18.", "A fast jump or long detector gap can break continuity."],
                ["Lost state", "Two fresh misses are needed; visible box may be held for 900 ms and identity can remain for re-acquisition.", "Held boxes are stale estimates, not fresh detections."],
            ],
            styles,
            widths=[27 * mm, 92 * mm, 48 * mm],
        )
    )
    story.append(
        para(
            "Appearance signatures sample the central 80% of a target into an 8x8 representation. They combine an HSV histogram (8 hue x 4 saturation bins), a 64-bit grayscale hash, and aspect ratio. Visible face appearance is accepted at composite similarity >= 0.72. This is a lightweight visual continuity heuristic, not biometric recognition.",
            styles["Body"],
        )
    )
    source_line(["follow_target_selector.dart", "follow_target_identity.dart", "appearance_signature_extractor.dart"], styles)

    add_heading(story, "5.4 Between-detector tracking", styles, 2)
    story.append(
        callout(
            "Naming versus implementation",
            "The class/file name says ObjectOpticalFlowTracker, but the current update path performs normalized template correlation with cv.matchTemplate, then transforms/reseeds sparse feature points. It does not call a Lucas-Kanade optical-flow function. The PDF uses 'frame-to-frame template tracker' when describing actual behavior.",
            styles,
            ORANGE,
        )
    )
    story.append(
        bullet_list(
            [
                "Grayscale input is downscaled to max 480, or 320 on iOS. Android reads the luma plane; iOS can use green as a fast luma proxy.",
                "Seed uses cv.goodFeaturesToTrack inside the central 80% of the target. It needs at least 12 features, can keep 80, and reseeds below 24 features or after 15 frames.",
                "Forward and backward template matches use central 80% crops, TM_CCOEFF_NORMED, a search area padded by max(0.75 box size, 0.08), and fixed frame-to-frame scale 1.0.",
                "Reject if similarity < 0.60, backward error > 1.5, center jump > 0.20, or scale outside 0.70..1.40. Failed tracking releases active mats/points.",
                "Delayed detector correction compares a historical box by frame ID, applies current delta with blend 0.35, clamps scale ratios 0.70..1.40, and re-seeds without resetting One Euro filters.",
                "Four One Euro filters smooth box edges (min cutoff 1.0, beta 0.10, derivative cutoff 1.0). Camera focus updates only after >=0.03 movement and >=400 ms.",
            ],
            styles,
        )
    )
    source_line(["object_optical_flow_tracker.dart", "object_tracking_frame.dart", "hand_gesture_thresholds.dart"], styles)
    story.append(PageBreak())
    return story


def object_backend_story(styles) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "6. Object detection backends", styles)
    story.append(
        para(
            "The home picker persists one backend by enum name. Android defaults to Native YOLO because MethodChannel support is true. iOS defaults to Ultralytics YOLO. Unsupported saved choices fall back to the platform default. Every service is single-flight, so a request arriving during inference is dropped.",
            styles["Lead"],
        )
    )
    story.append(
        data_table(
            [
                ["Backend", "Platform / model", "Input and gates", "Cadence / stabilization"],
                ["EfficientDet Lite", "All by enum; Android Lite2, iOS Lite0", "Android max 640 score >=0.60; iOS max 320 score >=0.35 and deny person; max 5", "350 ms, iOS 650 ms; empty hold 800 ms / 3 misses"],
                ["Ultralytics YOLO", "Android/iOS; model id yolo26n; GPU requested", "Upright JPEG quality 90; max 640 Android / 416 iOS; confidence 0.45; IoU 0.50; max 5", "350/650 ms; empty hold 1200 ms / 3; startup retry 5 s"],
                ["Google ML Kit", "Android/iOS native stream detector", "Multiple objects + classification; accepted label >=0.50 else 'Object'; max 5", "100 ms Android / 200 ms iOS; empty hold 600 ms / 3"],
                ["Native YOLO", "Android MethodChannel; yolov8n_oiv7.tflite; 601 classes; GPU requested", "YUV planes; confidence 0.25; class-aware IoU 0.50; max 5; strict frame/rotation/facing/space validation", "250 ms; empty hold 800 ms / 3; startup retry 5 s"],
                ["OpenCV SDK", "Experimental Android Java DNN; yolov8n_oiv7.onnx + TFLite metadata; 601 classes", "YUV planes; confidence 0.25; class-aware IoU 0.50; max 5; same response contract validation", "400 ms; empty hold 1000 ms / 3; startup retry 5 s"],
            ],
            styles,
            widths=[26 * mm, 43 * mm, 60 * mm, 38 * mm],
            font_size="TableTiny",
        )
    )
    story.append(
        callout(
            "Person ownership",
            "Every AppObjectDetection path filters the exact normalized label 'person'. Faces are supplied by ML Kit FaceDetector instead, preventing a person object box from competing with a face target.",
            styles,
        )
    )
    add_heading(story, "6.1 Preprocessing and coordinate contracts", styles, 2)
    story.append(
        bullet_list(
            [
                "Ultralytics converts BGRA/NV21/YUV420 camera data to an upright JPEG in a background isolate. The app maps normalized boxes back into its common image-size contract.",
                "ML Kit Android accepts direct one-plane NV21 or converts YUV planes to NV21 in background. iOS requires one BGRA8888 plane. Android rotation metadata can swap upright dimensions; iOS native boxes retain raw dimensions because rotation metadata is ignored there.",
                "Native YOLO and OpenCV send raw planes, row/pixel strides, frame ID, rotation degrees, and camera-facing name across MethodChannel. Results are accepted only when frame ID is new and coordinateSpace == upright_unmirrored with matching rotation/facing.",
                "All backends sort by confidence when available and cap at 5. ML Kit unclassified boxes have label 'Object', confidence null, class index -1, and may carry native tracking IDs.",
            ],
            styles,
        )
    )
    add_heading(story, "6.2 Result stabilization", styles, 2)
    story.append(
        para(
            "Each backend has separate empty-result holds, miss limits, normal/fast smoothing alpha, fast-motion threshold, maximum match distance, and partial-track holds. This improves visual continuity but means a visible box can outlive the detector result that created it. Those exact constants are listed in Appendix A.",
            styles["Body"],
        )
    )
    story.append(
        callout(
            "First-run dependency",
            "Ultralytics model resolution/download is prefetched after runApp and is intentionally not awaited. The UI can start before the model is ready. Network/model metadata failures are absorbed by prefetch, but a later backend startup can still fail and retry.",
            styles,
            ORANGE,
        )
    )
    source_line(["object_detection_service_factory.dart", "five *_object_detection_service.dart files", "object_detection_result_stabilizer.dart", "object_detection_target_smoother.dart", "two Android plugin packages"], styles)
    story.append(PageBreak())
    return story


def recording_pointer_training_story(styles) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "7. Recording, root hand pointer, debug tools, and training", styles)
    add_heading(story, "7.1 Recording lifecycle", styles, 2)
    story.append(
        data_table(
            [
                ["Operation", "Gesture / UI", "Implementation"],
                ["Start", "OK 1 s", "Paint loading overlay; wait end-of-frame + 120 ms; lock orientation; stop image stream; startVideoRecording with frame callback; timer starts; keep overlay 300 ms."],
                ["Pause/resume", "Punch 1 s", "Calls camera pause/resume and pauses/resumes elapsed timer; stream callback remains owned by recording API."],
                ["Stop", "Victory 2 s", "Paint overlay; wait; stopVideoRecording; Android copy attempt; unlock to portrait; reset timer; restart normal image stream; keep overlay 300 ms."],
                ["Camera switch/dispose", "UI/lifecycle", "Stops an active recording and attempts save before controller replacement/disposal; best-effort error handling."],
            ],
            styles,
            widths=[28 * mm, 32 * mm, 107 * mm],
        )
    )
    story.append(
        callout(
            "Silent recording and save-path mismatch",
            "All camera controllers use enableAudio: false. Android tries /storage/emulated/0/Download. Non-Android returns the camera XFile unchanged, but the snackbar still says 'Recording saved to Download folder'. These are current implementation limitations, not assumptions.",
            styles,
            RED,
        )
    )
    source_line(["recording_controls.dart", "camera_lifecycle.dart", "android/app/src/main/AndroidManifest.xml", "ios/Runner/Info.plist"], styles)

    add_heading(story, "7.2 Root point-8 dwell cursor", styles, 2)
    story.append(
        bullet_list(
            [
                "On home, a hidden front camera runs the same hand detector at max dimension 640 and uses the best reliable hand's index tip (landmark 8).",
                "detectionPointToPreviewCanvas maps detector coordinates through scale, rotation, and front-camera mirroring into the root overlay canvas.",
                "The overlay performs a Flutter hit test at the cursor and finds the first RenderSemanticsGestureHandler or RenderSemanticsAnnotations with a non-null onTap.",
                "Holding over the same enabled semantic target for exactly 2 seconds invokes onTap once. Leaving, losing point 8, changing target, or changing owner cancels/restarts progress.",
                "IgnorePointer makes ordinary touch pass through. Cursor is a yellow 11-pixel circle, black border, green 19-pixel progress arc, and label '8'.",
                "Before any camera route opens, the home camera is suspended/disposed. Live, debug, and training screens can publish an external pointer without opening a second camera.",
                "On the normal live gesture screen, showCursor is false when debug mode is off, but the hidden pointer can still activate semantic targets. Tests explicitly verify this behavior.",
            ],
            styles,
        )
    )
    story.append(
        callout(
            "Operational cost",
            "The home screen continuously owns a camera and runs hand inference while enabled. This can consume battery, heat the device, and conflict briefly with route camera release, which is why retry and watchdog logic exists.",
            styles,
            ORANGE,
        )
    )
    source_line(["home_hand_pointer_layer.dart", "camera_preview_geometry.dart", "home_hand_pointer_layer_test.dart"], styles)

    add_heading(story, "7.3 Hidden gesture diagnostics", styles, 2)
    story.append(
        para(
            "A reliable package I Love You pose opens the gesture debug selector after 3 matching frames and latches until 3 release frames. The selector offers one diagnostic family at a time: direction, Punch, Zoom In, Zoom Out, Return Main, recording, Call Me, and Follow Object, plus off/cancel/exit. Point 8 must dwell on a tile for 2 seconds. Opening the selector clears active gesture actions. Normal 21-point overlay remains except while the selector is open.",
            styles["Body"],
        )
    )
    source_line(["gesture_debug_menu_trigger.dart", "gesture_debug_selector_overlay.dart", "gesture_debug_evaluator.dart"], styles)

    add_heading(story, "7.4 Moving Down raw training collector", styles, 2)
    story.append(
        data_table(
            [
                ["Item", "Exact contract"],
                ["Availability", "Implemented but home list item disabled by showMovingDownTrainingListItem = false."],
                ["Capture", "Front camera preferred, high preset, no audio, portrait, exactly 2 seconds. Uses hands.first rather than live direction logic."],
                ["Record schema", "35 fields, schema_version 2. Includes raw dimensions/timestamps, processing FPS, palm/hand metadata, three 21x3 landmark arrays, labels, orientation, camera facing, and aliases."],
                ["Review filtering", "Only hand_detected == true and complete records remain; no-hand/malformed frames are excluded and valid records are reindexed from zero."],
                ["Acceptance", ">=12 valid frames; every x/y landmark within inclusive 0.05..0.95; one consistent physical handedness; strongest later palm-center y increase >=0.035."],
                ["Palm travel", "Average y of points 0,5,9,13,17. Measures largest later increase from highest earlier position, so a slight rise after a valid drop does not erase the sample."],
                ["Labels", "gesture_target MOVE_DOWN; static label IGNORE_STATIC; temporal label DIRECTION_DOWN; static_loss_enabled false; session_001."],
                ["File", "userN_direction_down_<UTC compact timestamp>Z.jsonl; one literal JSON object per line with trailing newline."],
                ["Storage", "Android MediaStore Download/moving down (legacy direct folder pre-Android Q). User IDs scan from user1000. Non-Android uses user1000 and system temp/moving down."],
                ["Review images", "JPEG max 360, quality 72, aligned to valid records for dialog only; never inserted into JSONL."],
            ],
            styles,
            widths=[36 * mm, 131 * mm],
        )
    )
    story.append(
        callout(
            "Not live classifier training",
            "The collector exports samples only. This repository contains no training script that consumes the JSONL, no newly trained temporal model, and no path that uses this exported data in live Move Down detection.",
            styles,
            RED,
        )
    )
    source_line(["moving_down_capture_screen.dart", "moving_down_capture_contract.dart", "moving_down_capture_metadata.dart", "MainActivity.java"], styles)
    story.append(PageBreak())
    return story


def platform_story(styles) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "8. Platform and storage matrix", styles)
    story.append(
        data_table(
            [
                ["Capability", "Android", "iOS", "Desktop/web boundary"],
                ["Primary camera frames", "YUV420", "One-plane BGRA8888", "Live code has BGRA fallback, but main product flags target mobile and object backends vary."],
                ["Hand interpreter", "Compiled attempted, XNNPACK fallback", "Compiled disabled; XNNPACK", "Vendored package declares desktop/web plugins, but app workflow is not validated here."],
                ["Object backends", "All 5; Native YOLO default", "EfficientDet, Ultralytics, ML Kit; Ultralytics default", "EfficientDet enum is always considered supported; other main flags false."],
                ["Face detector", "ML Kit fast + tracking", "ML Kit fast + tracking", "google_mlkit_face_detection is mobile-focused."],
                ["Recording", "Silent; copy attempt to public Download", "Silent; original XFile returned, despite Download snackbar", "Not verified."],
                ["Training JSONL", "MediaStore/direct Download/moving down", "System temporary directory", "System temporary directory if screen is reachable."],
                ["Permissions", "CAMERA; WRITE_EXTERNAL_STORAGE only through API 28; camera hardware required", "Camera and microphone descriptions; microphone is unused because audio false", "Platform-specific permission behavior not documented by app."],
            ],
            styles,
            widths=[32 * mm, 49 * mm, 49 * mm, 37 * mm],
            font_size="TableTiny",
        )
    )
    story.append(
        callout(
            "README platform drift",
            "README says iOS uses YUV420, but current live/home/debug/training code requests BGRA8888. README also describes audio-capable recordings and several obsolete gestures. Source and passing tests are authoritative for this document.",
            styles,
            ORANGE,
        )
    )
    add_heading(story, "8.1 Model assets in the repository", styles, 2)
    story.append(
        data_table(
            [
                ["Asset", "Size", "Use"],
                ["assets/models/yolov8n_oiv7.tflite", "14,067,409 bytes", "Android Native YOLO inference and OpenCV label metadata"],
                ["assets/models/yolov8n_oiv7.onnx", "14,066,896 bytes", "Experimental OpenCV Java DNN"],
                ["assets/models/yolo26n_w8a32.tflite", "2,875,544 bytes", "Bundled asset; selected Ultralytics service names model id yolo26n through package resolution"],
                ["assets/models/yolo26n.mlpackage.zip", "2,330,303 bytes", "Bundled Apple model archive; package/model preloader controls effective use"],
                ["hand_detection/hand_detection.tflite", "2,339,846 bytes", "Palm detector"],
                ["hand_detection/hand_landmark_full.tflite", "5,478,917 bytes", "21 image + world landmark model"],
                ["hand_detection/gesture_embedder.tflite", "546,000 bytes", "128-D gesture embedding"],
                ["hand_detection/canned_gesture_classifier.tflite", "7,773 bytes", "8-class canned gesture probabilities"],
            ],
            styles,
            widths=[64 * mm, 32 * mm, 71 * mm],
        )
    )
    source_line(["pubspec.yaml", "android/app/src/main/AndroidManifest.xml", "ios/Runner/Info.plist", "object_detection_backend.dart"], styles)
    story.append(PageBreak())
    return story


def limitations_story(styles) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "9. Limitations, mismatches, and failure modes", styles)
    story.append(
        para(
            "This chapter consolidates limitations that are otherwise easy to miss when reading individual classes. Severity describes impact on the product claim, not code quality.",
            styles["Lead"],
        )
    )
    rows = [
        ["Severity", "Area", "Current limitation", "Practical effect"],
        ["Critical", "Stand control", "No stand transport or motor API exists.", "Movement/follow/home/stop labels do not physically control a stand."],
        ["Critical", "Product modes", "Automatic Detect and Voice Command are placeholders.", "Only Hand Gesture opens the primary live feature."],
        ["High", "Thumb Up", "No 1-second hold and no stop/continue state/action.", "README and feature name overpromise."],
        ["High", "Return Main", "Current pose is four fingers down for 1 s, not circular index motion.", "README/demo instructions are wrong; only in-app state/camera zoom resets."],
        ["High", "Directions", "Static index pose, not swipe/trajectory; output is text only.", "Fast swipes can be rejected by steadiness and never command hardware."],
        ["High", "Recording", "enableAudio false; iOS save snackbar says Download while no copy occurs.", "Videos are silent and iOS storage messaging is inaccurate."],
        ["High", "Follow identity", "Heuristic labels/classes/tracking IDs/signatures, not persistent real-world identity.", "Similar or occluded targets can switch or be lost."],
        ["High", "Face", "Detection only, no recognition/authentication.", "'My face' is not verified as the current user."],
        ["Medium", "Hand count", "maxDetections = 1.", "No two-hand gestures or robust choice among multiple people."],
        ["Medium", "ML explainability", "Learned model weights/training data are not described in repo.", "Exact package pose boundaries and accuracy cannot be guaranteed from code."],
        ["Medium", "Latency", "Single-flight frame drops, backend throttles, asynchronous cycles, stale-result holds.", "Visible feedback can lag or briefly show held boxes."],
        ["Medium", "Tracker", "Named optical flow but uses template matching plus feature bookkeeping.", "May drift on texture repetition, lighting change, deformation, or occlusion."],
        ["Medium", "Home camera", "Continuously runs on home while enabled.", "Battery/thermal/privacy cost and camera route handoff contention."],
        ["Medium", "Object classes", "Person labels are always filtered; backends have different class sets/confidence semantics.", "Results differ by backend; unclassified ML Kit objects are generic."],
        ["Medium", "Storage", "Android recording uses direct /storage/emulated/0/Download and catches failures.", "Scoped-storage/device policy can leave only the original camera file."],
        ["Medium", "Training", "Collector exports data but no trainer/model integration exists.", "Captures do not improve the live detector by themselves."],
        ["Low", "README", "iOS frame format and several gesture descriptions drift from source.", "Developers following README can implement/test the wrong pose."],
        ["Low", "Accessibility", "No calibration, handedness preference, hold-duration setting, or alternative input tuning.", "Some users/hand shapes/mobility constraints may be underserved."],
    ]
    story.append(data_table(rows, styles, widths=[18 * mm, 29 * mm, 68 * mm, 52 * mm], font_size="TableTiny", long=True))
    add_heading(story, "9.1 Common real-world recognition failures", styles, 2)
    story.append(
        bullet_list(
            [
                "Hand too small, cropped, blurred, backlit, motion-blurred, or below hand/landmark confidence gates.",
                "Occluded fingertips/joints fail visibleLandmark requirements; Punch is especially strict because all 21 points must be inside.",
                "Front/back mirroring or rotation bugs can reverse a direction or move a box; the project has many mapper tests because this boundary is fragile.",
                "Depth estimates are model-relative and weighted, not metric camera depth. Perspective and palm orientation can change 3D ratios.",
                "Frame rate changes convert 'N consecutive frames' into different wall-clock delays. Only hold gestures use explicit DateTime durations.",
                "Camera zoom ranges and increments are device-specific; a 0.20 zoom-level change is not a universal visual magnification.",
                "Object detector labels/confidences differ by model. A selection can fail even when a human clearly sees the object.",
            ],
            styles,
        )
    )
    story.append(PageBreak())
    return story


def validation_story(styles, snapshot: dict[str, str], manifest: list[tuple[str, int, str]]) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "10. Verification performed for this reference", styles)
    story.append(
        data_table(
            [
                ["Check", "Result", "Meaning / boundary"],
                ["fvm flutter analyze", "PASS - No issues found", "Static analysis with pinned Flutter 3.41.7 on the current dirty working tree."],
                ["fvm flutter test", "PASS - 627 tests", "All repository Flutter tests passed. Output ended '+627: All tests passed!'."],
                ["Source audit", "PASS - app, vendored hand package, native packages, platform entrypoints", "Reviewed deterministic logic and generated Appendix A directly from constants; Appendix B hashes source/config files."],
                ["Real-hand media", "7 source-credited photos", "Images are illustrative only and licenses/sources are listed in Appendix C."],
                ["Device test", "NOT PERFORMED", "No physical Android/iOS camera run, performance benchmark, recording storage verification, or real-hand accuracy study in this task."],
                ["Coverage", "NOT CLAIMED", "627 passing tests do not imply every branch, model, plugin, or device behavior is covered."],
            ],
            styles,
            widths=[36 * mm, 43 * mm, 88 * mm],
        )
    )
    story.append(
        key_value_table(
            [
                ("Branch", snapshot["branch"]),
                ("HEAD", snapshot["head"]),
                ("Working tree", snapshot["status"]),
                ("Changed entries", snapshot["changed_count"]),
                ("Manifest rows", str(len(manifest))),
                ("Manifest text lines", f"{sum(lines for _, lines, _ in manifest):,}"),
            ],
            styles,
        )
    )
    story.append(
        callout(
            "What '100% accurate' can honestly mean",
            "Every deterministic statement in this PDF is tied to the current source snapshot. Runtime recognition accuracy cannot honestly be guaranteed at 100% because it depends on learned models, real hands, lighting, cameras, OS/plugin behavior, and hardware that were not exhaustively tested. Claiming otherwise would be less accurate, not more.",
            styles,
            BLUE,
        )
    )
    story.append(PageBreak())
    return story


def threshold_appendix_story(styles, constants: list[tuple[str, str, str]]) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "Appendix A. Every HandGestureThresholds constant", styles)
    story.append(
        para(
            f"The {len(constants)} declarations below are parsed directly from {THRESHOLD_FILE.relative_to(ROOT)} at generation time. Values are Dart expressions exactly as normalized to one line. This is the exhaustive tuning surface for app-owned gesture, follow, backend, stabilization, tracking, and cadence thresholds.",
            styles["Lead"],
        )
    )
    rows: list[list[object]] = [["Type", "Constant", "Dart value"]]
    for type_name, name, value in constants:
        rows.append([type_name, name, value])
    story.append(data_table(rows, styles, widths=[35 * mm, 63 * mm, 69 * mm], font_size="TableTiny", long=True))
    story.append(PageBreak())
    return story


def manifest_appendix_story(styles, manifest: list[tuple[str, int, str]]) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "Appendix B. Source and configuration manifest", styles)
    story.append(
        para(
            "This manifest lists current tracked plus untracked text source/config files, excluding tmp, output, .dart_tool, and build. SHA-256 is truncated to 12 hex characters for review. Generated assets and binary model internals are listed elsewhere, not decoded here.",
            styles["Lead"],
        )
    )
    groups: dict[str, int] = {}
    for path, _, _ in manifest:
        root = path.split("/", 1)[0]
        groups[root] = groups.get(root, 0) + 1
    story.append(
        data_table(
            [["Top-level group", "Files"]] + [[group, str(count)] for group, count in sorted(groups.items())],
            styles,
            widths=[120 * mm, 47 * mm],
        )
    )
    story.append(Spacer(1, 4 * mm))
    rows: list[list[object]] = [["Path", "Lines", "SHA-256/12"]]
    rows.extend([[path, str(lines), digest] for path, lines, digest in manifest])
    story.append(data_table(rows, styles, widths=[125 * mm, 17 * mm, 25 * mm], font_size="TableTiny", long=True))
    story.append(PageBreak())
    return story


def credits_appendix_story(styles) -> list[Flowable]:
    story: list[Flowable] = []
    add_heading(story, "Appendix C. Real-hand image credits", styles)
    story.append(
        para(
            "All photographs are loaded from local temporary copies at PDF generation time and reproduced without cropping or rotation; ReportLab only scales them to fit. Each image remains under its stated license. The PDF uses each only as an illustrative pose-family reference.",
            styles["Lead"],
        )
    )
    credits = [
        ["Use", "Wikimedia file / author", "License", "Source URL"],
        ["Open palm", "Hand.JPG / Jeremie63", "Public domain", "https://commons.wikimedia.org/wiki/File:Hand.JPG"],
        ["Pointing index", "Index finger 2.JPG / Than217", "Public domain", "https://commons.wikimedia.org/wiki/File:Index_finger_2.JPG"],
        ["Closed fist", "Closed fist.jpg / Cedar Tree", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Closed_fist.jpg"],
        ["OK", "OK Hand Gesture (cropped).jpg / faceofwiki", "CC0", "https://commons.wikimedia.org/wiki/File:OK_Hand_Gesture_(cropped).jpg"],
        ["Call-me/Shaka", "Shaka-sign.png / Roblespepe", "CC BY-SA 4.0", "https://commons.wikimedia.org/wiki/File:Shaka-sign.png"],
        ["Thumbs up", "Thumbs Up.JPG / faceofwiki", "CC0", "https://commons.wikimedia.org/wiki/File:Thumbs_Up.JPG"],
        ["Victory", "A Peace sign photo.jpg / Moyashi-otaku", "CC BY 4.0", "https://commons.wikimedia.org/wiki/File:A_Peace_sign_photo.jpg"],
    ]
    story.append(data_table(credits, styles, widths=[24 * mm, 62 * mm, 27 * mm, 54 * mm], font_size="TableTiny", long=True))
    story.append(Spacer(1, 5 * mm))
    story.append(
        callout(
            "License notice",
            "Attribution and license names are supplied for each included image. Follow the linked file description for complete license terms. Inclusion does not imply that any photographer endorses this application or document.",
            styles,
        )
    )
    add_heading(story, "Appendix C.1 Primary local sources", styles, 2)
    story.append(
        bullet_list(
            [
                "README.md and PROJECT_STRUCTURE.md were used as intent/history references, then checked against source.",
                "lib/main.dart and lib/hand_gesture_features define the current app behavior.",
                "third_party/hand_detection is vendored source version 3.3.0 and is included in the audit boundary.",
                "packages/native_object_detection and packages/opencv_object_detection define the Android app-owned inference bridges.",
                "android/app and ios/Runner define permissions, storage channel, labels, and platform launch behavior.",
                "test contains the 627 passing Flutter tests used for behavioral verification.",
            ],
            styles,
        )
    )
    return story


def build_pdf() -> Path:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    styles = build_styles()
    snapshot = git_snapshot()
    constants = parse_static_constants()
    manifest = source_manifest()

    story: list[Flowable] = []
    story.extend(cover_story(styles, snapshot))
    story.extend(toc_story(styles))
    story.extend(document_contract_story(styles))
    story.extend(overview_story(styles, manifest))
    story.extend(camera_hand_story(styles))
    story.extend(priority_story(styles))
    story.extend(gesture_story(styles))
    story.extend(follow_object_story(styles))
    story.extend(object_backend_story(styles))
    story.extend(recording_pointer_training_story(styles))
    story.extend(platform_story(styles))
    story.extend(limitations_story(styles))
    story.extend(validation_story(styles, snapshot, manifest))
    story.extend(threshold_appendix_story(styles, constants))
    story.extend(manifest_appendix_story(styles, manifest))
    story.extend(credits_appendix_story(styles))

    doc = ProjectDocTemplate(str(OUTPUT), styles)
    doc.multiBuild(story)
    return OUTPUT


if __name__ == "__main__":
    output = build_pdf()
    print(output)
