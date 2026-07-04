from __future__ import annotations

from datetime import date
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    ListFlowable,
    ListItem,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output" / "pdf" / "gesture_reference_13_gestures.pdf"


def p(text: str, style: ParagraphStyle) -> Paragraph:
    return Paragraph(escape(text).replace("\n", "<br/>"), style)


def bullet(items: list[str], styles) -> ListFlowable:
    return ListFlowable(
        [ListItem(p(item, styles["BodySmall"]), leftIndent=6) for item in items],
        bulletType="bullet",
        leftIndent=14,
        bulletFontSize=6,
        spaceBefore=2,
        spaceAfter=4,
    )


def info_table(rows: list[tuple[str, list[str]]], styles) -> Table:
    table_rows = []
    for label, values in rows:
        table_rows.append(
            [
                p(label, styles["FieldLabel"]),
                bullet(values, styles),
            ]
        )

    table = Table(table_rows, colWidths=[35 * mm, 132 * mm], hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#EEF3F8")),
                ("BOX", (0, 0), (-1, -1), 0.4, colors.HexColor("#B9C7D6")),
                ("INNERGRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#D7E0EA")),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def heading(text: str, styles) -> list:
    return [p(text, styles["H2"]), Spacer(1, 4)]


def gesture_section(number: int, gesture: dict, styles) -> list:
    story = []
    if number > 1:
        story.append(PageBreak())

    story.extend(heading(f"{number}. {gesture['name']}", styles))
    story.append(p(gesture["summary"], styles["Lead"]))
    story.append(Spacer(1, 5))
    story.append(
        info_table(
            [
                ("Code path", gesture["code_path"]),
                ("How to use in code", gesture["use_steps"]),
                ("Points used", gesture["points"]),
                ("Angles and thresholds", gesture["thresholds"]),
                ("Overlap priority", gesture["overlap"]),
            ],
            styles,
        )
    )
    return story


def build_styles():
    base = getSampleStyleSheet()
    styles = {
        "Title": ParagraphStyle(
            "Title",
            parent=base["Title"],
            fontName="Helvetica-Bold",
            fontSize=25,
            leading=30,
            alignment=TA_CENTER,
            textColor=colors.HexColor("#123047"),
            spaceAfter=8,
        ),
        "Subtitle": ParagraphStyle(
            "Subtitle",
            parent=base["BodyText"],
            fontSize=11,
            leading=15,
            alignment=TA_CENTER,
            textColor=colors.HexColor("#4A5B6B"),
            spaceAfter=14,
        ),
        "H1": ParagraphStyle(
            "H1",
            parent=base["Heading1"],
            fontName="Helvetica-Bold",
            fontSize=17,
            leading=21,
            textColor=colors.HexColor("#123047"),
            spaceBefore=8,
            spaceAfter=7,
        ),
        "H2": ParagraphStyle(
            "H2",
            parent=base["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=15,
            leading=19,
            textColor=colors.HexColor("#17496A"),
            spaceBefore=2,
            spaceAfter=3,
        ),
        "Lead": ParagraphStyle(
            "Lead",
            parent=base["BodyText"],
            fontSize=10.5,
            leading=14,
            textColor=colors.HexColor("#2A3946"),
            spaceAfter=5,
        ),
        "Body": ParagraphStyle(
            "Body",
            parent=base["BodyText"],
            fontSize=9.2,
            leading=12,
            textColor=colors.HexColor("#1F2D38"),
        ),
        "BodySmall": ParagraphStyle(
            "BodySmall",
            parent=base["BodyText"],
            fontSize=8.4,
            leading=10.8,
            textColor=colors.HexColor("#1F2D38"),
        ),
        "FieldLabel": ParagraphStyle(
            "FieldLabel",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=8.7,
            leading=11,
            textColor=colors.HexColor("#123047"),
        ),
        "TableHead": ParagraphStyle(
            "TableHead",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=8.4,
            leading=10.5,
            textColor=colors.white,
        ),
        "TableCell": ParagraphStyle(
            "TableCell",
            parent=base["BodyText"],
            fontSize=7.8,
            leading=9.6,
            textColor=colors.HexColor("#1F2D38"),
        ),
    }
    return styles


LANDMARKS = [
    ("0", "wrist", "Palm center, palm side checks, open palm orientation."),
    ("1", "thumbCMC", "Standard 21-point id; not referenced by this repo."),
    ("2", "thumbMCP", "Thumb angle, closed thumb, open palm thumb score."),
    ("3", "thumbIP", "Thumb angle, call gesture, closed thumb checks."),
    ("4", "thumbTip", "OK touch, call gesture, zoom, open palm, closed thumb."),
    ("5", "indexMCP", "Direction chain, index angle, circle gesture, palm center."),
    ("6", "indexPIP", "Direction chain, index angle, folded/open checks."),
    ("7", "indexDIP", "Direction chain and index circle direction point."),
    ("8", "indexTip", "Direction chain, OK touch, circle tracking, zoom."),
    ("9", "middleMCP", "Direction chain, palm center, open/folded checks."),
    ("10", "middlePIP", "Direction chain and angle/fold checks."),
    ("11", "middleDIP", "Direction chain."),
    ("12", "middleTip", "Direction chain and open/folded checks."),
    ("13", "ringMCP", "Direction chain, palm center, open/folded checks."),
    ("14", "ringPIP", "Direction chain and angle/fold checks."),
    ("15", "ringDIP", "Direction chain."),
    ("16", "ringTip", "Direction chain and open/folded checks."),
    ("17", "pinkyMCP", "Direction chain, palm center, open/folded checks."),
    ("18", "pinkyPIP", "Direction chain and angle/fold checks."),
    ("19", "pinkyDIP", "Direction chain."),
    ("20", "pinkyTip", "Direction chain, call gesture, open/folded checks."),
]


DIRECTION_POINTS = [
    "Index chain: indexFingerMCP -> indexFingerPIP -> indexFingerDIP -> indexFingerTip (ids 5, 6, 7, 8).",
    "Middle chain: middleFingerMCP -> middleFingerPIP -> middleFingerDIP -> middleFingerTip (ids 9, 10, 11, 12).",
    "Ring chain: ringFingerMCP -> ringFingerPIP -> ringFingerDIP -> ringFingerTip (ids 13, 14, 15, 16).",
    "Pinky chain: pinkyMCP -> pinkyPIP -> pinkyDIP -> pinkyTip (ids 17, 18, 19, 20).",
    "X is optionally mirrored before direction math; Y increases downward in image coordinates.",
]


DIRECTION_THRESHOLDS = [
    "A finger chain counts only when angle MCP-PIP-TIP is >= 160 deg.",
    "At least 3 accepted finger chains must agree on the same axis.",
    "Horizontal minimum distance = max(imageWidth * 0.025, fingerSpan * 0.18).",
    "Vertical minimum distance = max(imageHeight * 0.025, fingerSpan * 0.18).",
    "Horizontal dominance: abs(deltaX) >= abs(deltaY) * 0.45.",
    "Vertical dominance: abs(deltaY) >= abs(deltaX) * 0.45.",
]


GESTURES = [
    {
        "name": "Move Left",
        "summary": "Move or hold an extended hand/finger shape toward the left. The app reports Moving left.",
        "code_path": [
            "DirectionGestureDetector.detect(...) in lib/hand_gesture_features/domain/services/direction_gesture_detector.dart.",
            "Called from _updateGestureState after custom gestures, recording, zoom, and known package gestures have not won.",
        ],
        "use_steps": [
            "Get bestHand from the camera hand detector.",
            "Call _directionGestureDetector.detect(hand: bestHand, imageSize: detectionImageSize, mirrorHorizontally: mirrorDirectionalGestureCoordinates).",
            "If result == HandMoveDirection.left, show Moving left or send your stand-left command.",
        ],
        "points": DIRECTION_POINTS,
        "thresholds": DIRECTION_THRESHOLDS
        + [
            "Left condition: summed chain deltaX < 0 after mirroring, and horizontal rules pass.",
        ],
        "overlap": [
            "Direction is a fallback. It is skipped while follow-object, recording, zoom, or a known package gesture is active.",
            "Folded fingers no longer count as direction chains, which prevents zoom and fist poses from becoming left movement.",
        ],
    },
    {
        "name": "Move Right",
        "summary": "Move or hold an extended hand/finger shape toward the right. The app reports Moving right.",
        "code_path": [
            "DirectionGestureDetector.detect(...) in direction_gesture_detector.dart.",
            "The same four finger chains are checked as Move Left, but the X direction is positive.",
        ],
        "use_steps": [
            "Call DirectionGestureDetector.detect with the selected hand and detection image size.",
            "If result == HandMoveDirection.right, show Moving right or send your stand-right command.",
            "Keep mirrorHorizontally aligned with the preview/camera direction so left and right are user-visible directions.",
        ],
        "points": DIRECTION_POINTS,
        "thresholds": DIRECTION_THRESHOLDS
        + [
            "Right condition: summed chain deltaX > 0 after mirroring, and horizontal rules pass.",
        ],
        "overlap": [
            "Direction is checked only after higher-priority gestures are rejected.",
            "This stops thumbs-up and zoom from being displayed as movement.",
        ],
    },
    {
        "name": "Move Up",
        "summary": "Point or move an extended hand/finger shape upward. The app reports Moving up.",
        "code_path": [
            "DirectionGestureDetector.detect(...) in direction_gesture_detector.dart.",
            "README also documents pointing up as a Move Up input, but package pointingUp can also be shown as its own known gesture.",
        ],
        "use_steps": [
            "Call DirectionGestureDetector.detect after zoom and package gestures are checked.",
            "If result == HandMoveDirection.up, show Moving up or send your stand-up command.",
        ],
        "points": DIRECTION_POINTS,
        "thresholds": DIRECTION_THRESHOLDS
        + [
            "Up condition: summed chain deltaY < 0, because image Y gets smaller upward.",
        ],
        "overlap": [
            "Zoom is evaluated before movement. If a zoom pose is active, Move Up is skipped.",
            "Folded upward fingers are rejected by the >= 160 deg extension gate.",
        ],
    },
    {
        "name": "Move Down",
        "summary": "Point or move an extended hand/finger shape downward. The app reports Moving down.",
        "code_path": [
            "DirectionGestureDetector.detect(...) in direction_gesture_detector.dart.",
            "The same chain logic as Move Up is used, but the Y direction is positive.",
        ],
        "use_steps": [
            "Call DirectionGestureDetector.detect from the live gesture pipeline.",
            "If result == HandMoveDirection.down, show Moving down or send your stand-down command.",
        ],
        "points": DIRECTION_POINTS,
        "thresholds": DIRECTION_THRESHOLDS
        + [
            "Down condition: summed chain deltaY > 0, because image Y gets larger downward.",
        ],
        "overlap": [
            "Movement is ignored when follow tracking, custom gestures, recording, zoom, or known package gestures are active.",
        ],
    },
    {
        "name": "Detect My Face",
        "summary": "Hold the call-me hand shape for 2 seconds. The app then searches for the best face target.",
        "code_path": [
            "CustomGestureDetector._isCallMeGesture(...) sets rawCustomGestureResult.isCallMe.",
            "_updateGestureState holds _faceDetectGestureStartedAt until faceDetectHoldDuration is reached, then calls _selectBestFaceTarget(...).",
        ],
        "use_steps": [
            "Call _customGestureDetector.detect(...) for the selected hand.",
            "If result.isCallMe is true and no follow target is already locked, start/continue a 2 second hold timer.",
            "When hold progress reaches 1.0, call face detection and lock the best face target.",
        ],
        "points": [
            "Thumb: thumbTip and thumbIP (ids 4, 3).",
            "Pinky: pinkyTip and pinkyPIP (ids 20, 18).",
            "Closed fingers: indexTip/indexPIP (8, 6), middleTip/middlePIP (12, 10), ringTip/ringPIP (16, 14).",
            "Palm center: average of wrist plus index/middle/ring/pinky MCP points.",
        ],
        "thresholds": [
            "Thumb open: dist(thumbTip, palmCenter) > dist(thumbIP, palmCenter) * 1.15.",
            "Thumb reach: dist(thumbTip, palmCenter) > handSize * 0.23.",
            "Pinky open: tip distance > pip distance * 1.20 and tip distance > handSize * 0.30.",
            "Index, middle, ring closed: tip distance <= pip distance * 1.03 OR tip distance < handSize * 0.26.",
            "Thumb and pinky separation: dist(thumbTip, pinkyTip) > handSize * 0.55.",
            "Face detect hold: 2 seconds.",
        ],
        "overlap": [
            "This custom gesture runs before movement and zoom display, so it should not fall through to Moving left/up.",
        ],
    },
    {
        "name": "Follow The Object",
        "summary": "Open palm, hold, closed fist, then open palm again. The final hand-box center is used as the release point.",
        "code_path": [
            "FollowObjectSequenceDetector.update(...) controls the sequence.",
            "Open palm is custom geometry via OpenPalmGestureDetector. Closed fist in this sequence is package GestureType.closedFist.",
            "_selectFollowTargetAtReleasePoint(...) selects a face or object at release.",
        ],
        "use_steps": [
            "Show open palm and hold for followObjectFirstOpenPalmHoldDuration (1 second).",
            "Show closed fist; this moves the sequence to waitingForFinalOpen.",
            "Move the hand over the object/face and open palm again.",
            "Use releasePoint = center of hand.boundingBox to choose the target.",
        ],
        "points": [
            "Open palm uses wrist plus thumbMCP/thumbIP/thumbTip and index/middle/ring/pinky MCP/PIP/tip points.",
            "Open palm also uses indexTip, middleTip, ringTip, pinkyTip spread distances.",
            "Closed fist for this sequence is package-classified; this repo does not define its sequence points.",
            "Release point is not a landmark; it is the center of the detected hand bounding box.",
        ],
        "thresholds": [
            "Open palm enter confidence: 0.55; exit confidence: 0.45.",
            "Smoothing: 4 samples, at least 2 positive samples, max sample age 500 ms.",
            "Four fingers score angle 145..165 deg, tip/pip distance ratio 1.08..1.22, reach 0.25..0.34 of handSize.",
            "Thumb score angle 125..155 deg plus thumb reach and separation from index.",
            "Spread score uses indexTip to pinkyTip, adjacent tip distances, and indexMCP to pinkyMCP fan ratio.",
            "Closed fist package confidence: >= 0.50 for the follow sequence.",
        ],
        "overlap": [
            "While the follow sequence is active, custom gestures, recording, zoom, and movement are suppressed.",
        ],
    },
    {
        "name": "Stop and Continue Action",
        "summary": "Show thumbs-up. The current code displays Stop & Continue Action for a package thumbUp gesture.",
        "code_path": [
            "Package classifier result: hand.gesture.type == GestureType.thumbUp.",
            "Handled in _updateGestureState under hasKnownGesture.",
        ],
        "use_steps": [
            "Read bestHand.gesture after follow tracking and custom gestures are handled.",
            "Require gesture.type == GestureType.thumbUp and confidence >= minPackageGestureConfidence (0.50).",
            "Set gesture text or run your stop/continue command.",
            "README says hold 1 second; current code does not yet add a thumbUp hold timer.",
        ],
        "points": [
            "No direct landmark math for thumbUp exists in this repo.",
            "The hand_detection package decides thumbUp internally and returns GestureType.thumbUp.",
            "If you want local geometry later, use thumbTip/thumbIP/thumbMCP and folded index/middle/ring/pinky checks.",
        ],
        "thresholds": [
            "Package gesture confidence: >= 0.50.",
            "No repo-defined angle thresholds for thumbUp.",
        ],
        "overlap": [
            "Known package gestures now block generic movement, so thumbUp should not show Moving left.",
        ],
    },
    {
        "name": "Return To Main Position",
        "summary": "Rotate the index finger in a small circle while only the index finger is extended upward.",
        "code_path": [
            "CustomGestureDetector._detectCancelEverythingGesture(...).",
            "Result label: Return to main position. In the live screen this clears active tasks and resets camera zoom.",
        ],
        "use_steps": [
            "Call _customGestureDetector.detect(...) every processed frame.",
            "When result.isCancelEverything is true, call _clearAllActiveGestureTasks(resetCameraZoom: true).",
            "Keep passing mirrorHorizontally so index-tip circle points match visible direction.",
        ],
        "points": [
            "Index-only pose uses thumbTip/thumbIP/thumbMCP, indexMCP/indexPIP/indexDIP/indexTip, middle/ring/pinky MCP/PIP/tip.",
            "Circle history tracks only visible indexFingerTip (id 8).",
            "Palm center uses wrist and four MCP points.",
        ],
        "thresholds": [
            "Index extended: MCP-PIP-TIP angle >= 160 deg and tip distance > handSize * 0.30.",
            "Index faces up: indexTip.y < indexPIP.y and indexTip.y < palmCenter.y - handSize * 0.08.",
            "Index upright side offset: abs(indexTip.x - indexMCP.x) <= handSize * 0.50.",
            "Thumb closed: thumbTip to palm <= 0.30 * handSize; thumbTip to IP ratio <= 1.00.",
            "Thumb close to knuckles: min(thumbTip-indexMCP, thumbTip-middleMCP) <= 0.32 * handSize.",
            "Thumb not stretched: thumbTip-thumbMCP <= 0.36 * handSize.",
            "Middle, ring, pinky folded by angle: <= 145 deg.",
            "Circle history: max 36 samples, 1400 ms window, at least 5 samples.",
            "Circle radius: max(min(imageWidth, imageHeight) * 0.006, handSize * 0.015).",
            "Radius variation: <= averageRadius * 1.60.",
            "Total circular angle: abs(totalAngle) >= pi * 0.90.",
        ],
        "overlap": [
            "This custom gesture is handled before recording, zoom, package gestures, and direction movement.",
        ],
    },
    {
        "name": "Start Record Video",
        "summary": "Hold the OK gesture for 1 second. The app starts video recording.",
        "code_path": [
            "CustomGestureDetector._isOkGesture(...) sets customGestureResult.isOk.",
            "recording_controls.dart maps isOk to _RecordingGestureAction.start.",
        ],
        "use_steps": [
            "Call _customGestureDetector.detect(...) and require exactly one custom label.",
            "If result.isOk is true, pass _RecordingGestureAction.start to _updateRecordingGestureHold.",
            "After recordStartHoldDuration reaches 1 second, call _startGestureVideoRecording(controller).",
        ],
        "points": [
            "Thumb/index touch: thumbTip and indexTip (ids 4, 8).",
            "Index bend: indexMCP, indexPIP, indexTip (5, 6, 8).",
            "Open fingers: middle/ring/pinky MCP/PIP/tip.",
            "Palm center for extension checks.",
        ],
        "thresholds": [
            "Thumb-index touch distance <= max(handSize * 0.11, 12 px).",
            "Index bend angle MCP-PIP-TIP <= 150 deg.",
            "Middle/ring/pinky extended by angle: >= 160 deg and tip distance > handSize * 0.30.",
            "Hold duration: 1 second.",
            "Only allowed when not already recording.",
        ],
        "overlap": [
            "Recording gestures run before zoom and movement.",
            "If multiple custom gestures overlap, the app shows Hand detected instead of triggering recording.",
        ],
    },
    {
        "name": "Pause Video",
        "summary": "Make a fist and hold for 1 second. The app toggles pause/resume while recording.",
        "code_path": [
            "CustomGestureDetector._isPunchGesture(...) sets customGestureResult.isPunch.",
            "recording_controls.dart maps isPunch to _RecordingGestureAction.togglePause.",
        ],
        "use_steps": [
            "Call _customGestureDetector.detect(...) and require exactly one custom label.",
            "If result.isPunch is true and video is recording, pass togglePause to _updateRecordingGestureHold.",
            "After 1 second, call pauseVideoRecording() or resumeVideoRecording().",
        ],
        "points": [
            "Index, middle, ring, pinky tip/PIP/MCP points.",
            "Palm center for folded checks.",
            "Knuckle alignment uses y values of indexMCP, middleMCP, ringMCP, pinkyMCP.",
        ],
        "thresholds": [
            "Each finger folded: tip distance <= pip distance * 1.03 OR tip distance < handSize * 0.26.",
            "Knuckle Y spread <= handSize * 0.12.",
            "Package closedFist support can help when confidence >= 0.60, but fingers still must be closed.",
            "Hold duration: 1 second.",
            "Only allowed while video is already recording.",
        ],
        "overlap": [
            "Recording feedback suppresses movement and zoom while the hold is active.",
        ],
    },
    {
        "name": "End Record Video",
        "summary": "Hold the victory gesture for 2 seconds. The app stops and saves the recording.",
        "code_path": [
            "Package classifier result: hand.gesture.type == GestureType.victory.",
            "recording_controls.dart maps hasVictoryGesture to _RecordingGestureAction.stop.",
        ],
        "use_steps": [
            "Ensure follow tracking is not active and no custom gesture label is present.",
            "Require GestureType.victory with confidence >= 0.50.",
            "Pass _RecordingGestureAction.stop to _updateRecordingGestureHold.",
            "After 2 seconds, call _stopGestureVideoRecording(controller).",
        ],
        "points": [
            "No direct victory landmark math exists in this repo.",
            "The hand_detection package decides victory internally.",
            "Typical victory geometry would involve index/middle extended and ring/pinky folded, but that is not implemented here.",
        ],
        "thresholds": [
            "Package gesture confidence: >= 0.50.",
            "Hold duration: 2 seconds.",
            "Only allowed while video is recording.",
        ],
        "overlap": [
            "Victory is checked before zoom/movement and is used only for recording stop.",
        ],
    },
    {
        "name": "Zoom In",
        "summary": "Start with thumb and index pinched, hold briefly, then open them outward.",
        "code_path": [
            "ZoomGestureDetector.detect(...) state machine.",
            "_handleZoomDirection(ZoomDirection.zoomIn) applies camera zoom by +zoomStep.",
        ],
        "use_steps": [
            "Call _zoomGestureDetector.detect(...) after custom/recording checks and before movement.",
            "Start pose: thumb-index distance ratio is closed.",
            "Movement: open thumb/index enough within max gesture duration.",
            "If result == ZoomDirection.zoomIn, call _handleZoomDirection(result).",
        ],
        "points": [
            "Active pinch points: thumbTip and indexFingerTip (ids 4, 8).",
            "Middle/ring/pinky folded check uses their MCP/PIP/tip points.",
            "Palm center and hand bounding box define handSize and active tip-center distance.",
        ],
        "thresholds": [
            "Middle, ring, pinky folded by angle: <= 145 deg.",
            "Thumb/index distance ratio = dist(thumbTip, indexTip) / handSize.",
            "Valid active tips: center of thumbTip/indexTip must be farther than handSize * 0.06 from palm center.",
            "Closed start ratio: <= 0.26 and held for 500 ms.",
            "Open finish ratio: >= 0.27 and increased by at least 0.035.",
            "Gesture stable duration: >= 90 ms; max gesture duration: 2600 ms.",
            "Detected result is held for 650 ms. Camera zoom step is +0.2.",
        ],
        "overlap": [
            "Zoom is evaluated before direction movement, and active zoom blocks Move Up/Down/Left/Right.",
        ],
    },
    {
        "name": "Zoom Out",
        "summary": "Start with thumb and index open, hold briefly, then pinch them together.",
        "code_path": [
            "ZoomGestureDetector.detect(...) state machine.",
            "_handleZoomDirection(ZoomDirection.zoomOut) applies camera zoom by -zoomStep.",
        ],
        "use_steps": [
            "Call _zoomGestureDetector.detect(...) while no higher-priority custom/recording gesture is active.",
            "Start pose: thumb-index distance ratio is open.",
            "Movement: close thumb/index enough within max gesture duration.",
            "If result == ZoomDirection.zoomOut, call _handleZoomDirection(result).",
        ],
        "points": [
            "Active pinch points: thumbTip and indexFingerTip (ids 4, 8).",
            "Middle/ring/pinky folded check uses their MCP/PIP/tip points.",
            "Partial zoom-out recovery can use only thumbTip/indexTip divided by image max side.",
        ],
        "thresholds": [
            "Open start ratio: >= 0.27 and held for 500 ms.",
            "Closed finish ratio: <= 0.26 and decreased by at least 0.035.",
            "Gesture stable duration: >= 90 ms; max gesture duration: 2600 ms.",
            "Partial zoom-out open image ratio: >= 0.045.",
            "Partial close change: >= 0.018 and distance <= startDistance * 0.72.",
            "Detected result is held for 650 ms. Camera zoom step is -0.2.",
        ],
        "overlap": [
            "Zoom out uses the same priority protection as Zoom In and blocks generic movement while active.",
        ],
    },
]


def add_landmark_map(story, styles):
    story.append(PageBreak())
    story.extend(heading("Landmark Point Map Used By This Code", styles))
    story.append(
        p(
            "The code uses HandLandmarkType names. The numeric ids below follow the common 21-point hand landmark layout. "
            "This project directly references the listed names; id 1 is included only for orientation.",
            styles["Lead"],
        )
    )
    rows = [[p("ID", styles["TableHead"]), p("Code point", styles["TableHead"]), p("Where used", styles["TableHead"])]]
    for item in LANDMARKS:
        rows.append([p(item[0], styles["TableCell"]), p(item[1], styles["TableCell"]), p(item[2], styles["TableCell"])])
    table = Table(rows, colWidths=[13 * mm, 34 * mm, 119 * mm], repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#17496A")),
                ("BOX", (0, 0), (-1, -1), 0.4, colors.HexColor("#B9C7D6")),
                ("INNERGRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#D7E0EA")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    story.append(table)


def add_intro(story, styles):
    story.append(p("Gesture Detector", styles["Title"]))
    story.append(p("13 Gesture Code Reference", styles["Title"]))
    story.append(
        p(
            f"Generated from the current gesture_detector codebase on {date.today().isoformat()}. "
            "This guide documents how each gesture is used in code, which landmarks are read, and which thresholds/angles matter.",
            styles["Subtitle"],
        )
    )
    story.append(Spacer(1, 8))
    story.extend(heading("Live Detection Priority", styles))
    story.append(
        bullet(
            [
                "A camera frame is processed only every 100 ms or more.",
                "Hands below minHandScore 0.45 are ignored for main gesture actions.",
                "The app first evaluates cancel/OK/call/punch custom gestures and follow-object state.",
                "Recording holds are processed before zoom and movement.",
                "Zoom gestures run before generic movement so pinch gestures do not become Moving up.",
                "Known package gestures such as thumbUp and victory block generic movement.",
                "Generic direction movement is the fallback action.",
            ],
            styles,
        )
    )
    story.extend(heading("Common Geometry Helpers", styles))
    story.append(
        bullet(
            [
                "handSize = max(hand.boundingBox.width, hand.boundingBox.height).",
                "palmCenter = average of wrist, indexMCP, middleMCP, ringMCP, and pinkyMCP when available.",
                "fingerJointAngleDegrees(mcp, pip, tip) measures the PIP angle for non-thumb fingers.",
                "Visible landmarks require visibility >= 0.35, while zoom uses >= 0.30.",
                "Image Y grows downward, so upward motion has negative deltaY.",
            ],
            styles,
        )
    )


def add_footer(canvas, doc):
    canvas.saveState()
    width, _ = A4
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(colors.HexColor("#6A7A89"))
    canvas.drawString(18 * mm, 10 * mm, "gesture_detector - 13 gesture code reference")
    canvas.drawRightString(width - 18 * mm, 10 * mm, f"Page {doc.page}")
    canvas.restoreState()


def build_pdf():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    styles = build_styles()
    doc = SimpleDocTemplate(
        str(OUTPUT),
        pagesize=A4,
        rightMargin=16 * mm,
        leftMargin=16 * mm,
        topMargin=16 * mm,
        bottomMargin=16 * mm,
        title="Gesture Detector 13 Gesture Code Reference",
        author="Codex",
    )

    story = []
    add_intro(story, styles)
    add_landmark_map(story, styles)

    for index, gesture in enumerate(GESTURES, start=1):
        story.extend(gesture_section(index, gesture, styles))

    doc.build(story, onFirstPage=add_footer, onLaterPages=add_footer)
    return OUTPUT


if __name__ == "__main__":
    print(build_pdf())
