package com.grozziie.native_object_detection

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Android MethodChannel entry point for app-owned YOLO inference. */
class NativeObjectDetectionPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var flutterAssetLookup: (String) -> String
    private var executor: ExecutorService? = null
    private var detector: NativeYoloDetector? = null
    private val detecting = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        flutterAssetLookup = { asset ->
            binding.flutterAssets.getAssetFilePathByName(asset)
        }
        executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "native-yolo-detector")
        }
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "detect" -> detect(call, result)
            "getCapabilities" -> success(result, capabilities())
            "dispose" -> dispose(result)
            else -> result.notImplemented()
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        if (arguments == null) {
            result.error("invalid_arguments", "Initialization arguments are required.", null)
            return
        }
        val modelAsset = arguments["modelAsset"] as? String
        val confidenceThreshold = (arguments["confidenceThreshold"] as? Number)?.toFloat()
        val iouThreshold = (arguments["iouThreshold"] as? Number)?.toFloat()
        val maxResults = (arguments["maxResults"] as? Number)?.toInt()
        val expectedClassCount = (arguments["expectedClassCount"] as? Number)?.toInt()
        val useGpu = arguments["useGpu"] as? Boolean
        if (modelAsset.isNullOrBlank() ||
            confidenceThreshold == null || confidenceThreshold !in 0f..1f ||
            iouThreshold == null || iouThreshold !in 0f..1f ||
            maxResults == null || maxResults <= 0 ||
            expectedClassCount == null || expectedClassCount <= 0 ||
            useGpu == null
        ) {
            result.error("invalid_arguments", "Invalid detector initialization values.", null)
            return
        }

        submit(result, "model_load_failed") {
            val modelFile = copyFlutterAssetToCache(modelAsset)
            val replacement = NativeYoloDetector(
                modelFile = modelFile,
                confidenceThreshold = confidenceThreshold,
                iouThreshold = iouThreshold,
                maxResults = maxResults,
                expectedClassCount = expectedClassCount,
                useGpu = useGpu,
            )
            detector?.close()
            detector = replacement
            replacement.capabilities()
        }
    }

    private fun detect(call: MethodCall, result: MethodChannel.Result) {
        if (!detecting.compareAndSet(false, true)) {
            result.error("busy", "Native object detection is already running.", null)
            return
        }
        val frame = try {
            parseFrame(call.arguments as? Map<*, *>)
        } catch (error: Throwable) {
            detecting.set(false)
            result.error("invalid_frame", error.message, null)
            return
        }

        val worker = executor
        if (worker == null || worker.isShutdown) {
            detecting.set(false)
            result.error("detached", "Native object detector is detached.", null)
            return
        }
        worker.execute {
            try {
                val currentDetector = detector
                    ?: error("Native object detector has not been initialized.")
                val response = currentDetector.detect(frame)
                success(result, response)
            } catch (error: Throwable) {
                failure(result, "inference_failed", error)
            } finally {
                detecting.set(false)
            }
        }
    }

    private fun dispose(result: MethodChannel.Result) {
        submit(result, "dispose_failed") {
            detector?.close()
            detector = null
            mapOf("disposed" to true)
        }
    }

    private fun capabilities(): Map<String, Any?> {
        return detector?.capabilities() ?: mapOf(
            "platform" to "android",
            "initialized" to false,
            "accelerator" to null,
        )
    }

    private fun parseFrame(arguments: Map<*, *>?): NativeCameraFrame {
        requireNotNull(arguments) { "Frame arguments are required." }
        val planes = (arguments["planes"] as? List<*>)?.map { rawPlane ->
            val plane = rawPlane as? Map<*, *> ?: error("Invalid camera plane.")
            NativeImagePlane(
                bytes = plane["bytes"] as? ByteArray
                    ?: error("Camera plane bytes are required."),
                bytesPerRow = (plane["bytesPerRow"] as? Number)?.toInt()
                    ?: error("Camera row stride is required."),
                bytesPerPixel = (plane["bytesPerPixel"] as? Number)?.toInt()
                    ?: 1,
            )
        } ?: error("Camera planes are required.")

        return NativeCameraFrame(
            frameId = (arguments["frameId"] as? Number)?.toLong()
                ?: error("Frame ID is required."),
            width = (arguments["width"] as? Number)?.toInt()
                ?: error("Frame width is required."),
            height = (arguments["height"] as? Number)?.toInt()
                ?: error("Frame height is required."),
            format = arguments["format"] as? String
                ?: error("Frame format is required."),
            rotationDegrees = (arguments["rotationDegrees"] as? Number)?.toInt()
                ?: error("Frame rotation is required."),
            cameraFacing = arguments["cameraFacing"] as? String ?: "unknown",
            planes = planes,
        )
    }

    private fun copyFlutterAssetToCache(asset: String): File {
        val directory = File(context.codeCacheDir, "native_object_detection")
        check(directory.exists() || directory.mkdirs()) {
            "Could not create the native model cache directory."
        }
        val safeName = asset.substringAfterLast('/').replace(Regex("[^A-Za-z0-9._-]"), "_")
        val packageUpdate = context.packageManager
            .getPackageInfo(context.packageName, 0)
            .lastUpdateTime
        val destination = File(directory, "$safeName.$packageUpdate")
        if (destination.isFile && destination.length() > 0L) {
            return destination
        }
        val temporary = File(directory, "$safeName.$packageUpdate.tmp")
        context.assets.open(flutterAssetLookup(asset)).use { input ->
            temporary.outputStream().use { output -> input.copyTo(output) }
        }
        check(temporary.renameTo(destination)) { "Could not activate the cached model." }
        directory.listFiles()
            ?.filter { file ->
                file != destination &&
                    file.name.startsWith("$safeName.") &&
                    !file.name.endsWith(".tmp")
            }
            ?.forEach { stale -> runCatching { stale.delete() } }
        return destination
    }

    private fun submit(
        result: MethodChannel.Result,
        errorCode: String,
        operation: () -> Any?,
    ) {
        val worker = executor
        if (worker == null || worker.isShutdown) {
            result.error("detached", "Native object detector is detached.", null)
            return
        }
        worker.execute {
            try {
                success(result, operation())
            } catch (error: Throwable) {
                failure(result, errorCode, error)
            }
        }
    }

    private fun success(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun failure(result: MethodChannel.Result, code: String, error: Throwable) {
        mainHandler.post {
            result.error(code, error.message ?: error.javaClass.simpleName, null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        val worker = executor
        executor = null
        if (worker != null && !worker.isShutdown) {
            worker.execute {
                detector?.close()
                detector = null
            }
            worker.shutdown()
        }
    }

    private companion object {
        const val CHANNEL_NAME = "smart_stand/native_object_detection"
    }
}
