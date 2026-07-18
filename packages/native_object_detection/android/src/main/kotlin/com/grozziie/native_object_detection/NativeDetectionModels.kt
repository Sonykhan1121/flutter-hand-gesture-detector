package com.grozziie.native_object_detection

internal data class NativeImagePlane(
    val bytes: ByteArray,
    val bytesPerRow: Int,
    val bytesPerPixel: Int,
)

internal data class NativeCameraFrame(
    val frameId: Long,
    val width: Int,
    val height: Int,
    val format: String,
    val rotationDegrees: Int,
    val cameraFacing: String,
    val planes: List<NativeImagePlane>,
)

internal data class LetterboxTransform(
    val sourceWidth: Int,
    val sourceHeight: Int,
    val modelWidth: Int,
    val modelHeight: Int,
    val scale: Float,
    val padX: Float,
    val padY: Float,
)

internal data class PreprocessedFrame(
    val values: FloatArray,
    val uprightWidth: Int,
    val uprightHeight: Int,
    val transform: LetterboxTransform,
)

internal data class NativeDetection(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
    val label: String,
    val classIndex: Int,
    val confidence: Float,
) {
    fun asMap(): Map<String, Any?> = mapOf(
        "left" to left.toDouble(),
        "top" to top.toDouble(),
        "right" to right.toDouble(),
        "bottom" to bottom.toDouble(),
        "label" to label,
        "classIndex" to classIndex,
        "confidence" to confidence.toDouble(),
        "trackingId" to null,
    )
}
