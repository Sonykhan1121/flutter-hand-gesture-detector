from pathlib import Path

from PIL import Image
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
SOURCE_IMAGE = ROOT / "output/pdf/assets/hand_arrow_pose_reference.png"
ASSET_DIR = ROOT / "output/pdf/assets/direction_pose_crops"
OUTPUT_PDF = ROOT / "output/pdf/direction_exact_pose_blocker_reference.pdf"


class Rule(Flowable):
    def __init__(self, color=colors.HexColor("#D7DEE8"), width=1):
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


def paragraph_styles():
    styles = getSampleStyleSheet()
    styles.add(
        ParagraphStyle(
            name="TitleClean",
            parent=styles["Title"],
            fontName="Helvetica-Bold",
            fontSize=24,
            leading=30,
            textColor=colors.HexColor("#16202A"),
            spaceAfter=12,
        )
    )
    styles.add(
        ParagraphStyle(
            name="Section",
            parent=styles["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=15,
            leading=20,
            textColor=colors.HexColor("#26384C"),
            spaceBefore=8,
            spaceAfter=8,
        )
    )
    styles.add(
        ParagraphStyle(
            name="BodyClean",
            parent=styles["BodyText"],
            fontName="Helvetica",
            fontSize=10.5,
            leading=15,
            textColor=colors.HexColor("#263238"),
            spaceAfter=8,
        )
    )
    styles.add(
        ParagraphStyle(
            name="Small",
            parent=styles["BodyText"],
            fontName="Helvetica",
            fontSize=8.5,
            leading=11,
            textColor=colors.HexColor("#506070"),
        )
    )
    styles.add(
        ParagraphStyle(
            name="CardTitle",
            parent=styles["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=11,
            leading=13,
            textColor=colors.HexColor("#182536"),
            alignment=1,
            spaceAfter=4,
        )
    )
    styles.add(
        ParagraphStyle(
            name="CardText",
            parent=styles["BodyText"],
            fontName="Helvetica",
            fontSize=8.8,
            leading=11,
            textColor=colors.HexColor("#314357"),
            alignment=1,
        )
    )
    return styles


def make_pose_crops():
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE_IMAGE).convert("RGB")
    width, height = source.size

    crops = {
        "left": (35, 40, int(width * 0.49), int(height * 0.48)),
        "right": (int(width * 0.51), 40, width - 35, int(height * 0.48)),
        "up": (int(width * 0.10), int(height * 0.50), int(width * 0.54), height - 30),
    }

    output_paths = {}
    for name, box in crops.items():
        crop = source.crop(box)
        crop.thumbnail((900, 700), Image.Resampling.LANCZOS)
        out = ASSET_DIR / f"{name}_hand.png"
        crop.save(out, quality=95)
        output_paths[name] = out

    down = Image.open(output_paths["up"]).rotate(180, expand=True)
    down_out = ASSET_DIR / "down_hand.png"
    down.save(down_out, quality=95)
    output_paths["down"] = down_out
    return output_paths


def pose_card(styles, image_path, title, code_shape, explanation):
    image = RLImage(str(image_path), width=2.15 * inch, height=1.55 * inch, kind="proportional")
    title_p = Paragraph(title, styles["CardTitle"])
    shape_p = Paragraph(f"<font name='Courier-Bold'>{code_shape}</font>", styles["CardTitle"])
    text_p = Paragraph(explanation, styles["CardText"])
    return [title_p, image, Spacer(1, 4), shape_p, text_p]


def bullet(styles, text):
    return Paragraph(f"- {text}", styles["BodyClean"])


def build_pdf():
    styles = paragraph_styles()
    crops = make_pose_crops()

    doc = SimpleDocTemplate(
        str(OUTPUT_PDF),
        pagesize=letter,
        rightMargin=0.55 * inch,
        leftMargin=0.55 * inch,
        topMargin=0.55 * inch,
        bottomMargin=0.55 * inch,
        title="Direction Gesture Exact Pose Blocker",
        author="Codex",
    )

    story = []
    story.append(Paragraph("Direction Gesture: What Should Be Blocked", styles["TitleClean"]))
    story.append(
        Paragraph(
            "This PDF is my understanding of your request. You do not want to remove the current direction logic. "
            "You want to add one extra safety check: when the hand is held as a perfectly straight static arrow "
            "pose, the app should not say Moving left, Moving right, Moving up, or Moving down.",
            styles["BodyClean"],
        )
    )
    story.append(Rule())
    story.append(Paragraph("Main Meaning", styles["Section"]))
    story.append(
        Paragraph(
            "The blocked case is an exact static hand shape. It is not a real motion command. In code terms, "
            "after the existing detector chooses a direction, check whether all extended finger chains are almost "
            "perfectly straight in that same direction with almost no sideways drift. If yes, return none.",
            styles["BodyClean"],
        )
    )
    story.append(bullet(styles, "Keep current left/right/up/down detection for normal non-exact poses."))
    story.append(bullet(styles, "Only block the four exact straight arrow-like poses below."))
    story.append(bullet(styles, "Do not change zoom, recording, follow object, gesture priority, or camera mirroring."))
    story.append(PageBreak())

    story.append(Paragraph("Blocked Exact Hand Poses", styles["TitleClean"]))
    story.append(
        Paragraph(
            "These are the four static hand shapes that should return none instead of a movement label.",
            styles["BodyClean"],
        )
    )
    story.append(Spacer(1, 8))

    table_data = [
        [
            pose_card(
                styles,
                crops["left"],
                "Block left arrow pose",
                "<------",
                "Straight hand/fingers pointing left. Do not show Moving left.",
            ),
            pose_card(
                styles,
                crops["right"],
                "Block right arrow pose",
                "------>",
                "Straight hand/fingers pointing right. Do not show Moving right.",
            ),
        ],
        [
            pose_card(
                styles,
                crops["up"],
                "Block upper pose",
                "| upper",
                "Straight hand/fingers pointing up. Do not show Moving up.",
            ),
            pose_card(
                styles,
                crops["down"],
                "Block lower pose",
                "| lower",
                "Straight hand/fingers pointing down. Do not show Moving down.",
            ),
        ],
    ]
    table = Table(table_data, colWidths=[3.55 * inch, 3.55 * inch], rowHeights=[3.05 * inch, 3.05 * inch])
    table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#F8FAFC")),
                ("BOX", (0, 0), (-1, -1), 0.75, colors.HexColor("#D8E0EA")),
                ("INNERGRID", (0, 0), (-1, -1), 0.75, colors.HexColor("#D8E0EA")),
                ("LEFTPADDING", (0, 0), (-1, -1), 12),
                ("RIGHTPADDING", (0, 0), (-1, -1), 12),
                ("TOPPADDING", (0, 0), (-1, -1), 10),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
            ]
        )
    )
    story.append(table)
    story.append(PageBreak())

    story.append(Paragraph("What Should Still Work", styles["TitleClean"]))
    story.append(
        Paragraph(
            "The blocker should be strict. It should not cancel normal direction detections where the hand is not "
            "an exact straight arrow pose.",
            styles["BodyClean"],
        )
    )
    story.append(Rule())
    keep_items = [
        (
            "Majority direction",
            "If 3 finger chains point one way and another finger is different, the current detector can still return that direction.",
        ),
        (
            "Diagonal or imperfect pose",
            "If the fingers have visible cross-axis drift, such as right plus a little up, keep the existing stronger-axis decision.",
        ),
        (
            "Camera mirroring",
            "Front/back camera mirroring behavior should stay the same. The blocker should use the already mirrored visible X value.",
        ),
        (
            "Missing or folded fingers",
            "Existing none cases should remain none. This new rule is only an extra blocker after a direction was already selected.",
        ),
    ]
    rows = []
    for title, text in keep_items:
        rows.append([Paragraph(title, styles["CardTitle"]), Paragraph(text, styles["BodyClean"])])
    keep_table = Table(rows, colWidths=[1.85 * inch, 5.25 * inch])
    keep_table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FFFFFF")),
                ("BOX", (0, 0), (-1, -1), 0.75, colors.HexColor("#D8E0EA")),
                ("INNERGRID", (0, 0), (-1, -1), 0.75, colors.HexColor("#D8E0EA")),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    story.append(keep_table)
    story.append(Spacer(1, 12))
    story.append(
        KeepTogether(
            [
                Paragraph("Implementation Rule In One Sentence", styles["Section"]),
                Paragraph(
                    "Run the existing direction detector first; if it selects left, right, up, or down and every extended finger "
                    "chain forms a near-perfect straight arrow in that same direction, return none instead.",
                    styles["BodyClean"],
                ),
                Paragraph(
                    "Recommended strict tolerance: cross-axis movement should be no more than about 6 percent of the main-axis movement.",
                    styles["Small"],
                ),
            ]
        )
    )

    def add_footer(canvas, document):
        canvas.saveState()
        canvas.setFont("Helvetica", 8)
        canvas.setFillColor(colors.HexColor("#7A8795"))
        canvas.drawString(0.55 * inch, 0.30 * inch, "Direction gesture clarification")
        canvas.drawRightString(7.95 * inch, 0.30 * inch, f"Page {document.page}")
        canvas.restoreState()

    doc.build(story, onFirstPage=add_footer, onLaterPages=add_footer)


if __name__ == "__main__":
    build_pdf()
    print(OUTPUT_PDF)
