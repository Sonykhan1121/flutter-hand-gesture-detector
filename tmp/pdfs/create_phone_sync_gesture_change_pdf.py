from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    Flowable,
    Image as RLImage,
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[2]
SOURCE_SHADOW = ROOT / "assets" / "images" / "moving_down_shadow.png"
TMP_DIR = ROOT / "tmp" / "pdfs" / "phone_sync_gesture_change"
OUTPUT_PDF = ROOT / "output" / "pdf" / "phone_sync_gesture_change_proposal.pdf"


class Rule(Flowable):
    def __init__(self, color=colors.HexColor("#D9E2EC"), width=1):
        super().__init__()
        self.color = color
        self.width = width

    def wrap(self, avail_width, avail_height):
        self.avail_width = avail_width
        return avail_width, 8

    def draw(self):
        self.canv.setStrokeColor(self.color)
        self.canv.setLineWidth(self.width)
        self.canv.line(0, 4, self.avail_width, 4)


def styles():
    base = getSampleStyleSheet()
    return {
        "Title": ParagraphStyle(
            "Title",
            parent=base["Title"],
            fontName="Helvetica-Bold",
            fontSize=24,
            leading=29,
            textColor=colors.HexColor("#13293D"),
            spaceAfter=8,
        ),
        "Subtitle": ParagraphStyle(
            "Subtitle",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=10.5,
            leading=15,
            textColor=colors.HexColor("#536271"),
            spaceAfter=10,
        ),
        "Section": ParagraphStyle(
            "Section",
            parent=base["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=15,
            leading=20,
            textColor=colors.HexColor("#17324D"),
            spaceBefore=6,
            spaceAfter=7,
        ),
        "Body": ParagraphStyle(
            "Body",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=9.4,
            leading=13.2,
            textColor=colors.HexColor("#253545"),
            spaceAfter=6,
        ),
        "Small": ParagraphStyle(
            "Small",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=8.0,
            leading=10.5,
            textColor=colors.HexColor("#5F6F7F"),
        ),
        "CardTitle": ParagraphStyle(
            "CardTitle",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=11,
            leading=13,
            textColor=colors.HexColor("#13293D"),
            alignment=1,
            spaceAfter=4,
        ),
        "CardBody": ParagraphStyle(
            "CardBody",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=8.3,
            leading=10.8,
            textColor=colors.HexColor("#35495E"),
            alignment=1,
        ),
        "Badge": ParagraphStyle(
            "Badge",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=8.0,
            leading=10,
            textColor=colors.white,
            alignment=1,
        ),
    }


def load_shadow() -> Image.Image:
    shadow = Image.open(SOURCE_SHADOW).convert("RGBA")
    bbox = shadow.getbbox()
    if bbox:
        shadow = shadow.crop(bbox)
    alpha = shadow.getchannel("A")
    alpha = ImageEnhance.Contrast(alpha).enhance(1.12)
    shadow.putalpha(alpha)
    return shadow


def fit_image(image: Image.Image, max_size: tuple[int, int]) -> Image.Image:
    fitted = image.copy()
    fitted.thumbnail(max_size, Image.Resampling.LANCZOS)
    return fitted


def rotate_for_direction(shadow: Image.Image, direction: str) -> Image.Image:
    rotations = {
        "down": 0,
        "up": 180,
        "left": 270,
        "right": 90,
    }
    return shadow.rotate(rotations[direction], expand=True, resample=Image.Resampling.BICUBIC)


def draw_phone(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], accent: str) -> None:
    left, top, right, bottom = box
    draw.rounded_rectangle(
        (left + 5, top + 8, right + 5, bottom + 8),
        radius=22,
        fill=(20, 32, 43, 55),
    )
    draw.rounded_rectangle(
        box,
        radius=22,
        fill=(250, 253, 255, 255),
        outline=accent,
        width=4,
    )
    draw.rounded_rectangle(
        (left + 12, top + 18, right - 12, bottom - 22),
        radius=15,
        fill=(232, 242, 249, 255),
        outline=(180, 204, 220, 255),
        width=1,
    )
    draw.ellipse(((left + right) // 2 - 4, top + 8, (left + right) // 2 + 4, top + 16), fill=(40, 54, 67, 255))
    draw.rounded_rectangle(((left + right) // 2 - 13, bottom - 15, (left + right) // 2 + 13, bottom - 10), radius=3, fill=(130, 150, 165, 255))


def draw_person(draw: ImageDraw.ImageDraw, center: tuple[int, int], color: str) -> None:
    x, y = center
    draw.ellipse((x - 18, y - 42, x + 18, y - 6), fill=color)
    draw.rounded_rectangle((x - 25, y - 3, x + 25, y + 52), radius=18, fill=color)


def draw_arrow(
    draw: ImageDraw.ImageDraw,
    start: tuple[int, int],
    end: tuple[int, int],
    color: str,
    width: int = 7,
) -> None:
    draw.line((start, end), fill=color, width=width)
    angle = math.atan2(end[1] - start[1], end[0] - start[0])
    head_len = 22
    head_angle = math.radians(28)
    p1 = (
        end[0] - head_len * math.cos(angle - head_angle),
        end[1] - head_len * math.sin(angle - head_angle),
    )
    p2 = (
        end[0] - head_len * math.cos(angle + head_angle),
        end[1] - head_len * math.sin(angle + head_angle),
    )
    draw.polygon([end, p1, p2], fill=color)


def draw_motion_trail(draw: ImageDraw.ImageDraw, direction: str, accent: str) -> None:
    if direction == "left":
        points = [((455, 210), (270, 210)), ((430, 250), (300, 250))]
    elif direction == "right":
        points = [((265, 210), (450, 210)), ((290, 250), (420, 250))]
    elif direction == "up":
        points = [((360, 315), (360, 150)), ((405, 295), (405, 180))]
    else:
        points = [((360, 145), (360, 310)), ((405, 165), (405, 280))]

    for index, (start, end) in enumerate(points):
        draw_arrow(draw, start, end, accent, width=7 - index)


def direction_card(direction: str, title: str, label: str, accent: str) -> Path:
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGBA", (720, 470), (248, 251, 253, 255))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((16, 16, 704, 454), radius=30, fill=(255, 255, 255, 255), outline=(214, 226, 238, 255), width=2)
    draw.rounded_rectangle((36, 34, 210, 67), radius=16, fill=accent)
    draw.text((54, 43), label, fill=(255, 255, 255, 255))

    draw_person(draw, (95, 250), (44, 62, 80, 255))
    draw_person(draw, (625, 250), (44, 62, 80, 210))
    draw_phone(draw, (120, 145, 205, 310), accent)
    draw_phone(draw, (515, 145, 600, 310), accent)
    draw_motion_trail(draw, direction, accent)

    shadow = rotate_for_direction(load_shadow(), direction)
    shadow = fit_image(shadow, (210, 190))
    glow = Image.new("RGBA", shadow.size, (0, 0, 0, 0))
    glow.putalpha(shadow.getchannel("A").filter(ImageFilter.GaussianBlur(12)))
    glow = ImageEnhance.Brightness(glow).enhance(0.45)
    center = (360, 245)
    shadow_pos = (center[0] - shadow.width // 2, center[1] - shadow.height // 2)
    canvas.alpha_composite(glow, shadow_pos)
    canvas.alpha_composite(shadow, shadow_pos)

    draw = ImageDraw.Draw(canvas)
    draw.text((36, 392), title, fill=(20, 41, 61, 255))
    draw.text((36, 420), "Move the whole hand. Do not hold a static arrow pose.", fill=(82, 98, 113, 255))

    out = TMP_DIR / f"sync_{direction}.png"
    canvas.convert("RGB").save(out, quality=95)
    return out


def current_problem_image() -> Path:
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGBA", (1000, 560), (248, 251, 253, 255))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((22, 22, 978, 538), radius=34, fill=(255, 255, 255, 255), outline=(218, 228, 238, 255), width=2)
    draw.text((54, 48), "Current problem", fill=(20, 41, 61, 255))
    draw.text((54, 82), "The hand pose reads like traffic control, not phone sync.", fill=(82, 98, 113, 255))

    shadow = load_shadow()
    variants = [
        ("LEFT POSE", rotate_for_direction(shadow, "left"), (110, 190)),
        ("RIGHT POSE", rotate_for_direction(shadow, "right"), (380, 190)),
        ("DOWN POSE", rotate_for_direction(shadow, "down"), (650, 190)),
    ]
    for text, image, center in variants:
        image = fit_image(image, (185, 190))
        pos = (center[0] - image.width // 2, center[1] - image.height // 2)
        canvas.alpha_composite(image, pos)
        draw.rounded_rectangle((center[0] - 80, 380, center[0] + 80, 410), radius=14, fill=(238, 242, 246, 255))
        draw.text((center[0] - 52, 388), text, fill=(77, 91, 106, 255))

    draw.rounded_rectangle((760, 75, 930, 116), radius=19, fill=(216, 51, 64, 255))
    draw.text((786, 87), "CHANGE THIS", fill=(255, 255, 255, 255))
    out = TMP_DIR / "current_problem.png"
    canvas.convert("RGB").save(out, quality=95)
    return out


def concept_image() -> Path:
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGBA", (1000, 560), (246, 250, 252, 255))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((22, 22, 978, 538), radius=34, fill=(255, 255, 255, 255), outline=(214, 226, 238, 255), width=2)
    draw.text((54, 48), "New phone sync meaning", fill=(20, 41, 61, 255))
    draw.text((54, 82), "Open palm plus movement sends the sync direction from one phone/person to another.", fill=(82, 98, 113, 255))
    draw_person(draw, (150, 300), (44, 62, 80, 255))
    draw_person(draw, (850, 300), (44, 62, 80, 210))
    draw_phone(draw, (180, 180, 285, 380), "#0EA5E9")
    draw_phone(draw, (715, 180, 820, 380), "#0EA5E9")
    draw_arrow(draw, (335, 280), (655, 280), "#16A34A", width=10)
    draw_arrow(draw, (366, 235), (625, 235), "#0EA5E9", width=6)

    shadow = fit_image(load_shadow(), (205, 210))
    shadow = shadow.rotate(90, expand=True, resample=Image.Resampling.BICUBIC)
    shadow_pos = (500 - shadow.width // 2, 305 - shadow.height // 2)
    canvas.alpha_composite(shadow, shadow_pos)

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((376, 424, 624, 466), radius=20, fill=(22, 163, 74, 255))
    draw.text((410, 438), "SYNC RIGHT EXAMPLE", fill=(255, 255, 255, 255))
    out = TMP_DIR / "new_concept.png"
    canvas.convert("RGB").save(out, quality=95)
    return out


def rl_image(path: Path, width: float, height: float) -> RLImage:
    return RLImage(str(path), width=width, height=height, kind="proportional")


def card_flow(style_map, image_path: Path, title: str, body: str):
    return [
        Paragraph(title, style_map["CardTitle"]),
        rl_image(image_path, 3.05 * inch, 1.98 * inch),
        Spacer(1, 4),
        Paragraph(body, style_map["CardBody"]),
    ]


def build_pdf() -> None:
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_PDF.parent.mkdir(parents=True, exist_ok=True)
    style_map = styles()

    current_img = current_problem_image()
    concept_img = concept_image()
    cards = {
        "left": direction_card("left", "Sync Left", "SYNC LEFT", "#2563EB"),
        "right": direction_card("right", "Sync Right", "SYNC RIGHT", "#16A34A"),
        "up": direction_card("up", "Sync Up", "SYNC UP", "#7C3AED"),
        "down": direction_card("down", "Sync Down", "SYNC DOWN", "#EA580C"),
    }

    doc = SimpleDocTemplate(
        str(OUTPUT_PDF),
        pagesize=letter,
        rightMargin=0.55 * inch,
        leftMargin=0.55 * inch,
        topMargin=0.50 * inch,
        bottomMargin=0.50 * inch,
        title="Phone Sync Gesture Change Proposal",
        author="Codex",
    )

    story = [
        Paragraph("Phone Sync Gesture Change Proposal", style_map["Title"]),
        Paragraph(
            "Visual mockup for replacing traffic-police style direction poses with a clearer phone-sync gesture.",
            style_map["Subtitle"],
        ),
        Rule(),
        Paragraph("1. What should change", style_map["Section"]),
        rl_image(current_img, 7.0 * inch, 3.9 * inch),
        Spacer(1, 8),
        Paragraph(
            "The current direction idea depends on static hand shapes. Users may understand it as directing traffic or waving a hand, not syncing a phone from one person to another.",
            style_map["Body"],
        ),
        Paragraph(
            "Change target: stop presenting the gesture as a hand-arrow pose. Present it as a sync transfer from one phone/person to another.",
            style_map["Body"],
        ),
        PageBreak(),
        Paragraph("2. New visual meaning", style_map["Title"]),
        Paragraph(
            "Use a phone outline, two-person context, shadow hand, and motion trail arrows. The command is the direction of the hand movement.",
            style_map["Subtitle"],
        ),
        rl_image(concept_img, 7.0 * inch, 3.9 * inch),
        Spacer(1, 8),
        Paragraph(
            "Recommended gesture: show open palm near the phone-sync area, then move the whole hand left, right, up, or down. Static finger direction should not be enough.",
            style_map["Body"],
        ),
        PageBreak(),
        Paragraph("3. Four direction shadow images", style_map["Title"]),
        Paragraph(
            "These are the four visual targets I want to use in the app guidance and detector behavior.",
            style_map["Subtitle"],
        ),
    ]

    table = Table(
        [
            [
                card_flow(style_map, cards["left"], "Sync Left", "Hand shadow moves left between phones."),
                card_flow(style_map, cards["right"], "Sync Right", "Hand shadow moves right between phones."),
            ],
            [
                card_flow(style_map, cards["up"], "Sync Up", "Hand shadow moves upward, not just pointing up."),
                card_flow(style_map, cards["down"], "Sync Down", "Hand shadow moves downward, not just pointing down."),
            ],
        ],
        colWidths=[3.45 * inch, 3.45 * inch],
        rowHeights=[2.78 * inch, 2.78 * inch],
    )
    table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor("#D9E2EC")),
                ("INNERGRID", (0, 0), (-1, -1), 0.6, colors.HexColor("#D9E2EC")),
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#F8FAFC")),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    story.append(table)
    story.extend(
        [
            PageBreak(),
            Paragraph("4. Exact app changes proposed", style_map["Title"]),
            Paragraph("Detection change", style_map["Section"]),
            Paragraph(
                "Before: direction is detected from the way extended fingers point. After: direction is detected from whole-hand movement over time while the palm is visible.",
                style_map["Body"],
            ),
            Paragraph("User text change", style_map["Section"]),
            Paragraph(
                "Before: Moving left, Moving right, Moving up, Moving down. After: Sync left, Sync right, Sync up, Sync down.",
                style_map["Body"],
            ),
            Paragraph("Visual change", style_map["Section"]),
            Paragraph(
                "Before: hand-only shadow or flat arrow-like hand pose. After: shadow hand plus phone outline, person-to-person context, and motion trail arrow.",
                style_map["Body"],
            ),
            Paragraph("Keep unchanged", style_map["Section"]),
            Paragraph(
                "Zoom, recording, face detection, follow-object selection, and camera switching should stay the same. The change is only for the four direction commands.",
                style_map["Body"],
            ),
        ]
    )

    doc.build(story)


if __name__ == "__main__":
    build_pdf()
    print(OUTPUT_PDF)
