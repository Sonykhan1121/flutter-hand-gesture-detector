package com.grozziie.native_object_detection

import kotlin.math.max
import kotlin.math.min
import kotlin.math.floor
import kotlin.math.roundToInt

/** Converts an Android camera frame directly into a letterboxed YOLO tensor. */
internal object YuvFramePreprocessor {
    private const val LETTERBOX_VALUE = 114f / 255f

    fun preprocess(
        frame: NativeCameraFrame,
        modelWidth: Int,
        modelHeight: Int,
        channelsFirst: Boolean,
    ): PreprocessedFrame {
        require(frame.width > 0 && frame.height > 0) { "Invalid camera dimensions." }
        require(modelWidth > 0 && modelHeight > 0) { "Invalid model dimensions." }
        require(frame.rotationDegrees in setOf(0, 90, 180, 270)) {
            "Unsupported frame rotation ${frame.rotationDegrees}."
        }
        when (frame.format.lowercase()) {
            "yuv420" -> require(frame.planes.size >= 3) {
                "YUV420 frames require Y, U, and V planes."
            }
            "nv21" -> require(frame.planes.isNotEmpty()) {
                "NV21 frames require one packed plane."
            }
            else -> error("Unsupported Android camera format: ${frame.format}.")
        }

        val quarterTurn = frame.rotationDegrees == 90 || frame.rotationDegrees == 270
        val uprightWidth = if (quarterTurn) frame.height else frame.width
        val uprightHeight = if (quarterTurn) frame.width else frame.height
        val scale = min(
            modelWidth.toFloat() / uprightWidth,
            modelHeight.toFloat() / uprightHeight,
        )
        val resizedWidth = max(1, (uprightWidth * scale).roundToInt())
        val resizedHeight = max(1, (uprightHeight * scale).roundToInt())
        val padX = (modelWidth - resizedWidth) / 2f
        val padY = (modelHeight - resizedHeight) / 2f
        val transform = LetterboxTransform(
            sourceWidth = uprightWidth,
            sourceHeight = uprightHeight,
            modelWidth = modelWidth,
            modelHeight = modelHeight,
            scale = scale,
            padX = padX,
            padY = padY,
        )

        val values = FloatArray(modelWidth * modelHeight * 3)
        for (modelY in 0 until modelHeight) {
            for (modelX in 0 until modelWidth) {
                val insideImage = modelX >= padX &&
                    modelX < padX + resizedWidth &&
                    modelY >= padY &&
                    modelY < padY + resizedHeight
                if (!insideImage) {
                    writeRgb(
                        values,
                        modelX,
                        modelY,
                        modelWidth,
                        modelHeight,
                        channelsFirst,
                        LETTERBOX_VALUE,
                        LETTERBOX_VALUE,
                        LETTERBOX_VALUE,
                    )
                    continue
                }

                val uprightX = ((modelX + 0.5f - padX) / scale - 0.5f)
                    .coerceIn(0f, (uprightWidth - 1).toFloat())
                val uprightY = ((modelY + 0.5f - padY) / scale - 0.5f)
                    .coerceIn(0f, (uprightHeight - 1).toFloat())
                val (red, green, blue) = sampleRgbBilinear(
                    frame,
                    uprightX,
                    uprightY,
                    uprightWidth,
                    uprightHeight,
                )
                writeRgb(
                    values,
                    modelX,
                    modelY,
                    modelWidth,
                    modelHeight,
                    channelsFirst,
                    red,
                    green,
                    blue,
                )
            }
        }

        return PreprocessedFrame(values, uprightWidth, uprightHeight, transform)
    }

    private fun sampleRgbBilinear(
        frame: NativeCameraFrame,
        uprightX: Float,
        uprightY: Float,
        uprightWidth: Int,
        uprightHeight: Int,
    ): Triple<Float, Float, Float> {
        val x0 = floor(uprightX).toInt().coerceIn(0, uprightWidth - 1)
        val y0 = floor(uprightY).toInt().coerceIn(0, uprightHeight - 1)
        val x1 = min(x0 + 1, uprightWidth - 1)
        val y1 = min(y0 + 1, uprightHeight - 1)
        val xWeight = uprightX - x0
        val yWeight = uprightY - y0

        val topLeft = sampleRgb(frame, x0, y0)
        val topRight = sampleRgb(frame, x1, y0)
        val bottomLeft = sampleRgb(frame, x0, y1)
        val bottomRight = sampleRgb(frame, x1, y1)

        fun interpolate(channel: Int): Float {
            val top = lerp(topLeft[channel], topRight[channel], xWeight)
            val bottom = lerp(bottomLeft[channel], bottomRight[channel], xWeight)
            return lerp(top, bottom, yWeight)
        }
        return Triple(interpolate(0), interpolate(1), interpolate(2))
    }

    private fun sampleRgb(
        frame: NativeCameraFrame,
        uprightX: Int,
        uprightY: Int,
    ): FloatArray {
        val (rawX, rawY) = inverseRotate(
            uprightX,
            uprightY,
            frame.width,
            frame.height,
            frame.rotationDegrees,
        )
        val (y, u, v) = sampleYuv(frame, rawX, rawY)
        val yf = max(0f, y - 16f)
        val uf = u - 128f
        val vf = v - 128f
        return floatArrayOf(
            (1.164f * yf + 1.596f * vf).coerceIn(0f, 255f) / 255f,
            (1.164f * yf - 0.392f * uf - 0.813f * vf)
                .coerceIn(0f, 255f) / 255f,
            (1.164f * yf + 2.017f * uf).coerceIn(0f, 255f) / 255f,
        )
    }

    private fun lerp(start: Float, end: Float, amount: Float): Float =
        start + (end - start) * amount

    private fun inverseRotate(
        uprightX: Int,
        uprightY: Int,
        rawWidth: Int,
        rawHeight: Int,
        rotationDegrees: Int,
    ): Pair<Int, Int> = when (rotationDegrees) {
        90 -> Pair(uprightY, rawHeight - 1 - uprightX)
        180 -> Pair(rawWidth - 1 - uprightX, rawHeight - 1 - uprightY)
        270 -> Pair(rawWidth - 1 - uprightY, uprightX)
        else -> Pair(uprightX, uprightY)
    }

    private fun sampleYuv(frame: NativeCameraFrame, x: Int, y: Int): Triple<Float, Float, Float> {
        return if (frame.format.equals("nv21", ignoreCase = true)) {
            sampleNv21(frame, x, y)
        } else {
            sampleYuv420(frame, x, y)
        }
    }

    private fun sampleYuv420(
        frame: NativeCameraFrame,
        x: Int,
        y: Int,
    ): Triple<Float, Float, Float> {
        val yPlane = frame.planes[0]
        val uPlane = frame.planes[1]
        val vPlane = frame.planes[2]
        val yValue = planeValue(yPlane, x, y, 16)
        val chromaX = x / 2
        val chromaY = y / 2
        val uValue = planeValue(uPlane, chromaX, chromaY, 128)
        val vValue = planeValue(vPlane, chromaX, chromaY, 128)
        return Triple(yValue.toFloat(), uValue.toFloat(), vValue.toFloat())
    }

    private fun sampleNv21(
        frame: NativeCameraFrame,
        x: Int,
        y: Int,
    ): Triple<Float, Float, Float> {
        val plane = frame.planes[0]
        val yIndex = y * plane.bytesPerRow + x
        val chromaStart = plane.bytesPerRow * frame.height
        val chromaIndex = chromaStart + (y / 2) * plane.bytesPerRow + (x / 2) * 2
        val yValue = byteValue(plane.bytes, yIndex, 16)
        val vValue = byteValue(plane.bytes, chromaIndex, 128)
        val uValue = byteValue(plane.bytes, chromaIndex + 1, 128)
        return Triple(yValue.toFloat(), uValue.toFloat(), vValue.toFloat())
    }

    private fun planeValue(
        plane: NativeImagePlane,
        x: Int,
        y: Int,
        fallback: Int,
    ): Int {
        val index = y * plane.bytesPerRow + x * max(1, plane.bytesPerPixel)
        return byteValue(plane.bytes, index, fallback)
    }

    private fun byteValue(bytes: ByteArray, index: Int, fallback: Int): Int {
        if (index !in bytes.indices) return fallback
        return bytes[index].toInt() and 0xff
    }

    private fun writeRgb(
        output: FloatArray,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        channelsFirst: Boolean,
        red: Float,
        green: Float,
        blue: Float,
    ) {
        val pixel = y * width + x
        if (channelsFirst) {
            val planeSize = width * height
            output[pixel] = red
            output[planeSize + pixel] = green
            output[planeSize * 2 + pixel] = blue
        } else {
            val base = pixel * 3
            output[base] = red
            output[base + 1] = green
            output[base + 2] = blue
        }
    }
}
