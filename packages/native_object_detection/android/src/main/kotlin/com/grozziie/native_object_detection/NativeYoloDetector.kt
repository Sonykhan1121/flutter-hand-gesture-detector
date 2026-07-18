package com.grozziie.native_object_detection

import java.io.File
import kotlin.system.measureNanoTime

internal class NativeYoloDetector(
    modelFile: File,
    private val confidenceThreshold: Float,
    private val iouThreshold: Float,
    private val maxResults: Int,
    expectedClassCount: Int,
    useGpu: Boolean,
) : AutoCloseable {
    private val labels = ModelMetadataReader.readLabels(modelFile)
    private val runner = LiteRtRunner(modelFile, useGpu)

    init {
        try {
            require(labels.size == expectedClassCount) {
                "Expected $expectedClassCount model classes but found ${labels.size}."
            }
            val dimensions = runner.outputDimensions.filter { it > 0 }
            val featureCount = labels.size + BOX_FEATURE_COUNT
            val hasRawYoloLayout = dimensions.takeLast(2).contains(featureCount)
            val hasEndToEndLayout = dimensions.lastOrNull() == END_TO_END_FEATURE_COUNT
            require(hasRawYoloLayout || hasEndToEndLayout) {
                "The YOLO output ${runner.outputDimensions.contentToString()} does not " +
                    "match $featureCount features for ${labels.size} classes."
            }
        } catch (error: Throwable) {
            runner.close()
            throw error
        }
    }

    fun capabilities(initialized: Boolean = true): Map<String, Any?> = mapOf(
        "platform" to "android",
        "initialized" to initialized,
        "accelerator" to runner.accelerator,
        "inputWidth" to runner.inputWidth,
        "inputHeight" to runner.inputHeight,
        "inputLayout" to if (runner.channelsFirst) "NCHW" else "NHWC",
        "outputDimensions" to runner.outputDimensions.toList(),
        "classCount" to labels.size,
    )

    fun detect(frame: NativeCameraFrame): Map<String, Any?> {
        lateinit var preprocessed: PreprocessedFrame
        lateinit var detections: List<NativeDetection>
        val elapsedNanos = measureNanoTime {
            preprocessed = YuvFramePreprocessor.preprocess(
                frame,
                modelWidth = runner.inputWidth,
                modelHeight = runner.inputHeight,
                channelsFirst = runner.channelsFirst,
            )
            val output = runner.run(preprocessed.values)
            detections = YoloPostprocessor.decode(
                output = output,
                outputDimensions = runner.outputDimensions,
                labels = labels,
                transform = preprocessed.transform,
                confidenceThreshold = confidenceThreshold,
                iouThreshold = iouThreshold,
                maxResults = maxResults,
            )
        }
        return mapOf(
            "frameId" to frame.frameId,
            "imageWidth" to preprocessed.uprightWidth,
            "imageHeight" to preprocessed.uprightHeight,
            "rotationDegrees" to frame.rotationDegrees,
            "cameraFacing" to frame.cameraFacing,
            "coordinateSpace" to "upright_unmirrored",
            "inferenceMs" to elapsedNanos / 1_000_000.0,
            "accelerator" to runner.accelerator,
            "detections" to detections.map { it.asMap() },
        )
    }

    override fun close() = runner.close()

    private companion object {
        const val BOX_FEATURE_COUNT = 4
        const val END_TO_END_FEATURE_COUNT = 6
    }
}
