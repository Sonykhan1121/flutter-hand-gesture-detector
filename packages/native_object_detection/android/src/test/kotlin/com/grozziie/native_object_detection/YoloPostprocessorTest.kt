package com.grozziie.native_object_detection

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class YoloPostprocessorTest {
    @Test
    fun `filters person and suppresses overlapping boxes`() {
        val anchors = 3
        val output = FloatArray(6 * anchors)
        setAnchor(output, anchors, 0, 320f, 320f, 300f, 300f, 0.95f, 0.10f)
        setAnchor(output, anchors, 1, 320f, 320f, 320f, 320f, 0.05f, 0.90f)
        setAnchor(output, anchors, 2, 325f, 325f, 320f, 320f, 0.05f, 0.80f)

        val detections = YoloPostprocessor.decode(
            output = output,
            outputDimensions = intArrayOf(1, 6, anchors),
            labels = listOf("person", "bottle"),
            transform = transform(sourceWidth = 640, sourceHeight = 640),
            confidenceThreshold = 0.60f,
            iouThreshold = 0.50f,
            maxResults = 5,
        )

        assertEquals(1, detections.size)
        assertEquals("bottle", detections.single().label)
        assertEquals(1, detections.single().classIndex)
        assertEquals(0.90f, detections.single().confidence, 0.0001f)
    }

    @Test
    fun `removes letterbox padding and returns normalized source boxes`() {
        val output = FloatArray(6)
        setAnchor(output, 1, 0, 320f, 320f, 320f, 160f, 0.05f, 0.90f)

        val detections = YoloPostprocessor.decode(
            output = output,
            outputDimensions = intArrayOf(1, 6, 1),
            labels = listOf("person", "bottle"),
            transform = transform(sourceWidth = 640, sourceHeight = 320),
            confidenceThreshold = 0.60f,
            iouThreshold = 0.50f,
            maxResults = 5,
        )

        val box = detections.single()
        assertEquals(0.25f, box.left, 0.0001f)
        assertEquals(0.25f, box.top, 0.0001f)
        assertEquals(0.75f, box.right, 0.0001f)
        assertEquals(0.75f, box.bottom, 0.0001f)
        assertTrue(box.right > box.left && box.bottom > box.top)
    }

    private fun setAnchor(
        output: FloatArray,
        anchorCount: Int,
        anchor: Int,
        centerX: Float,
        centerY: Float,
        width: Float,
        height: Float,
        personScore: Float,
        bottleScore: Float,
    ) {
        output[anchor] = centerX
        output[anchorCount + anchor] = centerY
        output[anchorCount * 2 + anchor] = width
        output[anchorCount * 3 + anchor] = height
        output[anchorCount * 4 + anchor] = personScore
        output[anchorCount * 5 + anchor] = bottleScore
    }

    private fun transform(sourceWidth: Int, sourceHeight: Int): LetterboxTransform {
        val scale = minOf(640f / sourceWidth, 640f / sourceHeight)
        return LetterboxTransform(
            sourceWidth = sourceWidth,
            sourceHeight = sourceHeight,
            modelWidth = 640,
            modelHeight = 640,
            scale = scale,
            padX = (640 - sourceWidth * scale) / 2f,
            padY = (640 - sourceHeight * scale) / 2f,
        )
    }
}
