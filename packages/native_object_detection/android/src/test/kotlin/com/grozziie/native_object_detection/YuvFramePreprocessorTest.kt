package com.grozziie.native_object_detection

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class YuvFramePreprocessorTest {
    @Test
    fun `reports upright dimensions for every rotation`() {
        val expectedSizes = mapOf(
            0 to Pair(4, 2),
            90 to Pair(2, 4),
            180 to Pair(4, 2),
            270 to Pair(2, 4),
        )

        for ((rotation, expected) in expectedSizes) {
            val result = YuvFramePreprocessor.preprocess(
                frame(rotation),
                modelWidth = 4,
                modelHeight = 4,
                channelsFirst = true,
            )

            assertEquals(expected.first, result.uprightWidth)
            assertEquals(expected.second, result.uprightHeight)
            assertEquals(4 * 4 * 3, result.values.size)
            assertTrue(result.values.all { it.isFinite() && it in 0f..1f })
        }
    }

    @Test
    fun `writes matching neutral pixels in NCHW and NHWC layouts`() {
        val nchw = YuvFramePreprocessor.preprocess(
            frame(0),
            modelWidth = 4,
            modelHeight = 2,
            channelsFirst = true,
        )
        val nhwc = YuvFramePreprocessor.preprocess(
            frame(0),
            modelWidth = 4,
            modelHeight = 2,
            channelsFirst = false,
        )

        assertEquals(nhwc.values[0], nchw.values[0], 0.0001f)
        assertEquals(nhwc.values[1], nchw.values[8], 0.0001f)
        assertEquals(nhwc.values[2], nchw.values[16], 0.0001f)
    }

    @Test
    fun `bilinearly interpolates between source pixels`() {
        val result = YuvFramePreprocessor.preprocess(
            NativeCameraFrame(
                frameId = 1,
                width = 2,
                height = 1,
                format = "yuv420",
                rotationDegrees = 0,
                cameraFacing = "back",
                planes = listOf(
                    NativeImagePlane(byteArrayOf(16, 235.toByte()), 2, 1),
                    NativeImagePlane(byteArrayOf(128.toByte()), 1, 1),
                    NativeImagePlane(byteArrayOf(128.toByte()), 1, 1),
                ),
            ),
            modelWidth = 4,
            modelHeight = 2,
            channelsFirst = false,
        )

        val reds = listOf(0, 1, 2, 3).map { pixel -> result.values[pixel * 3] }
        assertTrue(reds[0] < reds[1])
        assertTrue(reds[1] < reds[2])
        assertTrue(reds[2] < reds[3])
        assertTrue(reds[1] in 0.20f..0.30f)
        assertTrue(reds[2] in 0.70f..0.80f)
    }

    private fun frame(rotation: Int): NativeCameraFrame = NativeCameraFrame(
        frameId = 1,
        width = 4,
        height = 2,
        format = "yuv420",
        rotationDegrees = rotation,
        cameraFacing = "front",
        planes = listOf(
            NativeImagePlane(ByteArray(8) { 128.toByte() }, 4, 1),
            NativeImagePlane(ByteArray(2) { 128.toByte() }, 2, 1),
            NativeImagePlane(ByteArray(2) { 128.toByte() }, 2, 1),
        ),
    )
}
