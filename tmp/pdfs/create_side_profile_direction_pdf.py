from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    Flowable,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "output" / "pdf"
PDF_PATH = OUT_DIR / "direction_side_profile_pose_blocker_reference.pdf"


class SideProfileHand(Flowable):
    """Draws an original side-profile hand pose pointing right by default."""

    def __init__(self, width=220, height=110, orientation="right", label=None):
        super().__init__()
        self.width = width
        self.height = height
        self.orientation = orientation
        self.label = label

    def draw(self):
        c = self.canv
        c.saveState()

        c.translate(self.width / 2, self.height / 2)
        if self.orientation == "left":
            c.rotate(180)
        elif self.orientation == "up":
            c.rotate(90)
        elif self.orientation == "down":
            c.rotate(-90)

        scale = min(self.width / 340, self.height / 150)
        c.scale(scale, scale)
        c.translate(-170, 0)

        c.setStrokeColor(colors.HexColor("#111111"))
        c.setLineWidth(3.1)
        c.setLineJoin(1)
        c.setLineCap(1)

        # Original side-view hand outline: wrist/palm on the left, fingers together on the right,
        # and thumb visible underneath. This is intentionally a clean diagram, not a copied asset.
        outline = c.beginPath()
        outline.moveTo(23, -3)
        outline.curveTo(9, 20, 22, 48, 53, 58)
        outline.curveTo(83, 68, 116, 58, 151, 61)
        outline.curveTo(184, 64, 222, 75, 262, 77)
        outline.curveTo(298, 79, 316, 75, 319, 64)
        outline.curveTo(322, 51, 306, 47, 279, 50)
        outline.curveTo(294, 44, 305, 36, 302, 27)
        outline.curveTo(298, 17, 281, 18, 258, 24)
        outline.curveTo(229, 32, 200, 36, 174, 31)
        outline.curveTo(195, 22, 225, 13, 253, 11)
        outline.curveTo(282, 8, 297, 2, 295, -9)
        outline.curveTo(292, -21, 273, -20, 244, -13)
        outline.curveTo(215, -6, 187, -5, 160, -14)
        outline.curveTo(146, -19, 134, -24, 122, -28)
        outline.curveTo(143, -42, 158, -56, 149, -68)
        outline.curveTo(139, -82, 111, -63, 92, -46)
        outline.curveTo(70, -53, 50, -51, 37, -39)
        outline.curveTo(19, -23, 12, -10, 23, -3)
        c.drawPath(outline, stroke=1, fill=0)

        c.setLineWidth(2.15)
        inner = c.beginPath()
        inner.moveTo(157, 50)
        inner.curveTo(190, 68, 225, 68, 282, 63)
        c.drawPath(inner, stroke=1, fill=0)

        inner = c.beginPath()
        inner.moveTo(149, 37)
        inner.curveTo(185, 49, 221, 48, 278, 43)
        c.drawPath(inner, stroke=1, fill=0)

        inner = c.beginPath()
        inner.moveTo(141, 20)
        inner.curveTo(178, 33, 220, 29, 262, 21)
        c.drawPath(inner, stroke=1, fill=0)

        thumb = c.beginPath()
        thumb.moveTo(95, -45)
        thumb.curveTo(112, -30, 131, -19, 161, -14)
        c.drawPath(thumb, stroke=1, fill=0)

        palm = c.beginPath()
        palm.moveTo(92, -46)
        palm.curveTo(103, -29, 116, -25, 122, -28)
        c.drawPath(palm, stroke=1, fill=0)

        c.restoreState()


class PoseCard(Flowable):
    def __init__(self, title, subtitle, orientation):
        super().__init__()
        self.title = title
        self.subtitle = subtitle
        self.orientation = orientation
        self.width = 250
        self.height = 205

    def draw(self):
        c = self.canv
        c.saveState()
        c.setStrokeColor(colors.HexColor("#d9dee7"))
        c.setFillColor(colors.HexColor("#ffffff"))
        c.roundRect(0, 0, self.width, self.height, 8, stroke=1, fill=1)

        c.setFillColor(colors.HexColor("#111827"))
        c.setFont("Helvetica-Bold", 15)
        c.drawString(16, self.height - 28, self.title)

        c.setFillColor(colors.HexColor("#4b5563"))
        c.setFont("Helvetica", 9.4)
        c.drawString(16, self.height - 45, self.subtitle)

        if self.orientation in {"up", "down"}:
            hand = SideProfileHand(width=120, height=145, orientation=self.orientation)
            hand_x = 65
            hand_y = 8
        else:
            hand = SideProfileHand(width=210, height=120, orientation=self.orientation)
            hand_x = 20
            hand_y = 42

        hand.canv = c
        c.saveState()
        c.translate(hand_x, hand_y)
        hand.draw()
        c.restoreState()
        c.restoreState()


class TwoColumnPoseGrid(Flowable):
    def __init__(self):
        super().__init__()
        self.width = 520
        self.height = 430
        self.cards = [
            PoseCard("Block: Moving left", "Exact side-profile hand pointing left", "left"),
            PoseCard("Block: Moving right", "Exact side-profile hand pointing right", "right"),
            PoseCard("Block: Moving up", "Same side-profile pose rotated upward", "up"),
            PoseCard("Block: Moving down", "Same side-profile pose rotated downward", "down"),
        ]

    def draw(self):
        positions = [(0, 225), (270, 225), (0, 0), (270, 0)]
        for card, (x, y) in zip(self.cards, positions):
            card.canv = self.canv
            self.canv.saveState()
            self.canv.translate(x, y)
            card.draw()
            self.canv.restoreState()


def paragraph(text, style):
    return Paragraph(text, style)


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.HexColor("#6b7280"))
    canvas.drawRightString(letter[0] - 0.6 * inch, 0.35 * inch, f"Page {doc.page}")
    canvas.restoreState()


def build_pdf():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    styles = getSampleStyleSheet()
    styles.add(
        ParagraphStyle(
            name="Title2",
            parent=styles["Title"],
            fontName="Helvetica-Bold",
            fontSize=25,
            leading=30,
            textColor=colors.HexColor("#111827"),
            spaceAfter=14,
        )
    )
    styles.add(
        ParagraphStyle(
            name="Subtle",
            parent=styles["BodyText"],
            fontName="Helvetica",
            fontSize=10.5,
            leading=15,
            textColor=colors.HexColor("#374151"),
            spaceAfter=10,
        )
    )
    styles.add(
        ParagraphStyle(
            name="Section",
            parent=styles["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=17,
            leading=21,
            textColor=colors.HexColor("#111827"),
            spaceBefore=8,
            spaceAfter=8,
        )
    )
    styles.add(
        ParagraphStyle(
            name="Small",
            parent=styles["BodyText"],
            fontName="Helvetica",
            fontSize=9.5,
            leading=13,
            textColor=colors.HexColor("#374151"),
        )
    )

    doc = SimpleDocTemplate(
        str(PDF_PATH),
        pagesize=letter,
        rightMargin=0.62 * inch,
        leftMargin=0.62 * inch,
        topMargin=0.6 * inch,
        bottomMargin=0.55 * inch,
        title="Direction Gesture Side Profile Pose Blocker",
        author="Codex",
    )

    story = []
    story.append(paragraph("Direction Gesture: Side-Profile Pose Blocker", styles["Title2"]))
    story.append(
        paragraph(
            "Now I understand the shape: it is not a front-palm or back-hand photo. "
            "It is a sideways/profile hand, like the fingers are stretched together as one thin arrow shape.",
            styles["Subtle"],
        )
    )
    story.append(SideProfileHand(width=480, height=180, orientation="right"))
    story.append(Spacer(1, 10))
    story.append(paragraph("Meaning", styles["Section"]))
    story.append(
        paragraph(
            "When the hand is held in this exact side-profile static pose, the app should not detect it as "
            "Moving left, Moving right, Moving up, or Moving down. The hand is only posing like an arrow; "
            "it is not a movement command.",
            styles["Subtle"],
        )
    )
    story.append(
        paragraph(
            "Important: this does not mean all side-looking hands should be ignored. Only the very straight "
            "near-perfect profile pose should be blocked.",
            styles["Subtle"],
        )
    )

    story.append(PageBreak())
    story.append(paragraph("The Four Poses To Block", styles["Title2"]))
    story.append(
        paragraph(
            "Use the same side-profile hand shape for all four directions. Flip it for left or right, "
            "and rotate it for up or down.",
            styles["Subtle"],
        )
    )
    story.append(Spacer(1, 8))
    story.append(TwoColumnPoseGrid())

    story.append(PageBreak())
    story.append(paragraph("Code Logic I Understand", styles["Title2"]))
    story.append(
        paragraph(
            "Keep the current direction detector. Add only one strict blocker after it already chooses a direction.",
            styles["Subtle"],
        )
    )

    data = [
        [
            paragraph("<b>Case</b>", styles["Small"]),
            paragraph("<b>What should happen</b>", styles["Small"]),
        ],
        [
            paragraph("Exact profile hand pointing left", styles["Small"]),
            paragraph("Return none instead of Moving left.", styles["Small"]),
        ],
        [
            paragraph("Exact profile hand pointing right", styles["Small"]),
            paragraph("Return none instead of Moving right.", styles["Small"]),
        ],
        [
            paragraph("Exact profile hand pointing up", styles["Small"]),
            paragraph("Return none instead of Moving up.", styles["Small"]),
        ],
        [
            paragraph("Exact profile hand pointing down", styles["Small"]),
            paragraph("Return none instead of Moving down.", styles["Small"]),
        ],
        [
            paragraph("Diagonal or imperfect pose", styles["Small"]),
            paragraph("Do not block. Keep your existing direction result.", styles["Small"]),
        ],
        [
            paragraph("Majority direction with one finger different", styles["Small"]),
            paragraph("Do not block. Keep the existing majority logic.", styles["Small"]),
        ],
        [
            paragraph("Zoom, recording, follow-object, package gestures", styles["Small"]),
            paragraph("Do not change their priority or behavior.", styles["Small"]),
        ],
    ]
    table = Table(data, colWidths=[2.15 * inch, 4.35 * inch], repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#eef2ff")),
                ("BOX", (0, 0), (-1, -1), 0.75, colors.HexColor("#d9dee7")),
                ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#d9dee7")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    story.append(table)
    story.append(Spacer(1, 14))
    story.append(paragraph("Strict Blocker Rule", styles["Section"]))
    story.append(
        paragraph(
            "After the detector chooses left, right, up, or down, check the extended finger chains. "
            "If every contributing chain points in the same selected direction and the cross-axis drift is tiny, "
            "return HandMoveDirection.none. A tolerance around 0.06 means the pose must be almost perfectly straight.",
            styles["Subtle"],
        )
    )
    story.append(
        paragraph(
            "So the blocker is only for this exact side-profile arrow pose. It should not change normal movement, "
            "normal imperfect hand shapes, mirroring behavior, or higher-priority gestures.",
            styles["Subtle"],
        )
    )

    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    return PDF_PATH


if __name__ == "__main__":
    print(build_pdf())
