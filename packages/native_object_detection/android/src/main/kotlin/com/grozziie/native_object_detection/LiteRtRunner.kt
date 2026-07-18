package com.grozziie.native_object_detection

import android.util.Log
import com.google.ai.edge.litert.Accelerator
import com.google.ai.edge.litert.CompiledModel
import com.google.ai.edge.litert.TensorBuffer
import java.io.File

/** Minimal LiteRT 2.x float-input/float-output runner for one YOLO model. */
internal class LiteRtRunner(
    private val modelFile: File,
    useGpu: Boolean,
) : AutoCloseable {
    private data class Prepared(
        val model: CompiledModel,
        val inputs: List<TensorBuffer>,
        val outputs: List<TensorBuffer>,
        val inputDimensions: IntArray,
        val outputDimensions: IntArray,
    )

    private lateinit var model: CompiledModel
    private lateinit var inputs: List<TensorBuffer>
    private lateinit var outputs: List<TensorBuffer>

    var accelerator: String = "CPU"
        private set
    var inputDimensions: IntArray = IntArray(0)
        private set
    var outputDimensions: IntArray = IntArray(0)
        private set
    var channelsFirst: Boolean = false
        private set
    var inputWidth: Int = 0
        private set
    var inputHeight: Int = 0
        private set

    init {
        var prepared: Prepared? = null
        var selectedAccelerator = "CPU"
        if (useGpu) {
            try {
                prepared = prepare(modelFile, Accelerator.GPU)
                selectedAccelerator = "GPU"
            } catch (error: Throwable) {
                Log.w(TAG, "GPU model preparation failed; using CPU.", error)
            }
        }
        if (prepared == null) {
            prepared = prepare(modelFile, Accelerator.CPU)
            selectedAccelerator = "CPU"
        }

        install(prepared, selectedAccelerator)

        Log.i(
            TAG,
            "LiteRT ready on $accelerator; input=${inputDimensions.contentToString()} " +
                "output=${outputDimensions.contentToString()}",
        )
    }

    @Synchronized
    fun run(values: FloatArray): FloatArray {
        val expected = inputWidth * inputHeight * 3
        require(values.size == expected) {
            "Expected $expected input floats but received ${values.size}."
        }
        return try {
            runOnce(values)
        } catch (gpuError: Throwable) {
            if (accelerator != "GPU") throw gpuError
            Log.w(TAG, "GPU inference failed; rebuilding the model on CPU.", gpuError)
            val cpuPrepared = try {
                prepare(modelFile, Accelerator.CPU)
            } catch (cpuPreparationError: Throwable) {
                cpuPreparationError.addSuppressed(gpuError)
                throw cpuPreparationError
            }
            closeCurrent()
            install(cpuPrepared, "CPU")
            runOnce(values)
        }
    }

    private fun runOnce(values: FloatArray): FloatArray {
        inputs.first().writeFloat(values)
        model.run(inputs, outputs)
        return outputs.first().readFloat()
    }

    private fun install(prepared: Prepared, selectedAccelerator: String) {
        try {
            validateInputDimensions(prepared.inputDimensions)
        } catch (error: Throwable) {
            closePrepared(prepared)
            throw error
        }
        model = prepared.model
        inputs = prepared.inputs
        outputs = prepared.outputs
        inputDimensions = prepared.inputDimensions
        outputDimensions = prepared.outputDimensions
        accelerator = selectedAccelerator
        channelsFirst = inputDimensions[1] == 3 && inputDimensions.last() != 3
        inputHeight = if (channelsFirst) inputDimensions[2] else inputDimensions[1]
        inputWidth = if (channelsFirst) inputDimensions[3] else inputDimensions[2]
    }

    private fun validateInputDimensions(dimensions: IntArray) {
        require(dimensions.size >= 4 && dimensions[0] == 1) {
            "Expected a four-dimensional, single-batch YOLO input tensor; " +
                "found ${dimensions.contentToString()}."
        }
        val isChannelsFirst = dimensions[1] == 3 && dimensions.last() != 3
        require(isChannelsFirst || dimensions.last() == 3) {
            "Expected a three-channel YOLO input tensor; " +
                "found ${dimensions.contentToString()}."
        }
        val height = if (isChannelsFirst) dimensions[2] else dimensions[1]
        val width = if (isChannelsFirst) dimensions[3] else dimensions[2]
        require(width > 0 && height > 0) { "Invalid YOLO input dimensions." }
    }

    private fun prepare(modelFile: File, accelerator: Accelerator): Prepared {
        val compiledModel = CompiledModel.create(
            modelFile.absolutePath,
            CompiledModel.Options(accelerator),
        )
        val inputBuffers: List<TensorBuffer>
        val outputBuffers: List<TensorBuffer>
        try {
            inputBuffers = compiledModel.createInputBuffers()
            outputBuffers = compiledModel.createOutputBuffers()
        } catch (error: Throwable) {
            runCatching { compiledModel.close() }
            throw error
        }

        try {
            require(inputBuffers.size == 1 && outputBuffers.isNotEmpty()) {
                "Expected one input and at least one output tensor."
            }
            val inputType = sequenceOf(
                "inputs_0",
                "args_0",
                "images",
                "input",
                "input_1",
            )
                .firstNotNullOfOrNull { name ->
                    runCatching { compiledModel.getInputTensorType(inputName = name) }.getOrNull()
                } ?: error("Could not inspect the YOLO input tensor.")
            val inputShape = inputType.layout?.dimensions?.toIntArray()
                ?: error("The YOLO input tensor has no dimensions.")
            val outputType = sequenceOf("output_0", "Identity")
                .firstNotNullOfOrNull { name ->
                    runCatching { compiledModel.getOutputTensorType(outputName = name) }.getOrNull()
                }
            val outputShape = outputType?.layout?.dimensions?.toIntArray() ?: IntArray(0)
            val elementCount = inputShape.fold(1) { total, dimension -> total * dimension }
            require(elementCount > 0) { "The YOLO input tensor is empty." }

            inputBuffers.first().writeFloat(FloatArray(elementCount))
            compiledModel.run(inputBuffers, outputBuffers)
            outputBuffers.first().readFloat()
            return Prepared(
                compiledModel,
                inputBuffers,
                outputBuffers,
                inputShape,
                outputShape,
            )
        } catch (error: Throwable) {
            closeBuffers(inputBuffers, outputBuffers)
            runCatching { compiledModel.close() }
            throw error
        }
    }

    override fun close() {
        closeCurrent()
    }

    private fun closeCurrent() {
        if (::inputs.isInitialized && ::outputs.isInitialized) {
            closeBuffers(inputs, outputs)
        }
        if (::model.isInitialized) runCatching { model.close() }
    }

    private fun closePrepared(prepared: Prepared) {
        closeBuffers(prepared.inputs, prepared.outputs)
        runCatching { prepared.model.close() }
    }

    private fun closeBuffers(inputs: List<TensorBuffer>, outputs: List<TensorBuffer>) {
        inputs.forEach { runCatching { it.close() } }
        outputs.forEach { runCatching { it.close() } }
    }

    private companion object {
        const val TAG = "NativeObjectDetection"
    }
}
