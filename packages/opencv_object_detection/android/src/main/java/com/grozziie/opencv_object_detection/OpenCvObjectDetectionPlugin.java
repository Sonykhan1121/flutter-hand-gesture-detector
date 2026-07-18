package com.grozziie.opencv_object_detection;

import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.opencv.android.OpenCVLoader;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Android MethodChannel entry point for the app-owned OpenCV Java detector. */
public final class OpenCvObjectDetectionPlugin
        implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private static final String TAG = "OpenCvObjectDetection";
    private static final String CHANNEL_NAME = "smart_stand/opencv_object_detection";

    private final AtomicBoolean detecting = new AtomicBoolean(false);
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private MethodChannel channel;
    private Context context;
    private FlutterPlugin.FlutterAssets flutterAssets;
    private ExecutorService executor;
    private OpenCvObjectDetector detector;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        flutterAssets = binding.getFlutterAssets();
        executor = Executors.newSingleThreadExecutor(runnable ->
                new Thread(runnable, "opencv-object-detector")
        );
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "initialize" -> initialize(call, result);
            case "detect" -> detect(call, result);
            case "getCapabilities" -> success(result, capabilities());
            case "dispose" -> dispose(result);
            default -> result.notImplemented();
        }
    }

    private void initialize(MethodCall call, MethodChannel.Result result) {
        Map<?, ?> arguments = asMap(call.arguments);
        if (arguments == null) {
            result.error("invalid_arguments", "Initialization arguments are required.", null);
            return;
        }
        String modelAsset = arguments.get("modelAsset") instanceof String
                ? (String) arguments.get("modelAsset")
                : null;
        String metadataAsset = arguments.get("metadataAsset") instanceof String
                ? (String) arguments.get("metadataAsset")
                : null;
        Float confidenceThreshold = floatValue(arguments.get("confidenceThreshold"));
        Float iouThreshold = floatValue(arguments.get("iouThreshold"));
        Integer maxResults = integerValue(arguments.get("maxResults"));
        Integer expectedClassCount = integerValue(arguments.get("expectedClassCount"));
        if (modelAsset == null
                || modelAsset.trim().isEmpty()
                || metadataAsset == null
                || metadataAsset.trim().isEmpty()
                || confidenceThreshold == null
                || confidenceThreshold < 0f
                || confidenceThreshold > 1f
                || iouThreshold == null
                || iouThreshold < 0f
                || iouThreshold > 1f
                || maxResults == null
                || maxResults <= 0
                || expectedClassCount == null
                || expectedClassCount <= 0) {
            result.error("invalid_arguments", "Invalid detector initialization values.", null);
            return;
        }

        submit(result, "model_load_failed", () -> {
            if (!OpenCVLoader.initLocal()) {
                throw new IllegalStateException("OpenCVLoader.initLocal() returned false.");
            }
            File modelFile = copyFlutterAssetToCache(modelAsset);
            File metadataFile = modelAsset.equals(metadataAsset)
                    ? modelFile
                    : copyFlutterAssetToCache(metadataAsset);
            OpenCvObjectDetector replacement = new OpenCvObjectDetector(
                    modelFile,
                    metadataFile,
                    confidenceThreshold,
                    iouThreshold,
                    maxResults,
                    expectedClassCount
            );
            OpenCvObjectDetector oldDetector = detector;
            detector = replacement;
            if (oldDetector != null) oldDetector.close();
            return replacement.capabilities(true);
        });
    }

    private void detect(MethodCall call, MethodChannel.Result result) {
        if (!detecting.compareAndSet(false, true)) {
            result.error("busy", "OpenCV object detection is already running.", null);
            return;
        }
        DetectionModels.CameraFrame frame;
        try {
            frame = parseFrame(asMap(call.arguments));
        } catch (Throwable error) {
            detecting.set(false);
            result.error("invalid_frame", error.getMessage(), Log.getStackTraceString(error));
            return;
        }

        ExecutorService worker = executor;
        if (worker == null || worker.isShutdown()) {
            detecting.set(false);
            result.error("detached", "OpenCV object detector is detached.", null);
            return;
        }
        worker.execute(() -> {
            try {
                OpenCvObjectDetector currentDetector = detector;
                if (currentDetector == null) {
                    throw new IllegalStateException(
                            "OpenCV object detector has not been initialized."
                    );
                }
                Map<String, Object> response = currentDetector.detect(frame);
                success(result, response);
            } catch (Throwable error) {
                failure(result, "inference_failed", error);
            } finally {
                detecting.set(false);
            }
        });
    }

    private void dispose(MethodChannel.Result result) {
        submit(result, "dispose_failed", () -> {
            OpenCvObjectDetector currentDetector = detector;
            detector = null;
            if (currentDetector != null) currentDetector.close();
            Map<String, Object> response = new LinkedHashMap<>();
            response.put("disposed", true);
            return response;
        });
    }

    private Map<String, Object> capabilities() {
        OpenCvObjectDetector currentDetector = detector;
        if (currentDetector != null) return currentDetector.capabilities(true);
        Map<String, Object> values = new LinkedHashMap<>();
        values.put("platform", "android");
        values.put("initialized", false);
        values.put("backend", "OpenCV DNN");
        values.put("target", "CPU");
        return values;
    }

    private DetectionModels.CameraFrame parseFrame(Map<?, ?> arguments) {
        if (arguments == null) {
            throw new IllegalArgumentException("Frame arguments are required.");
        }
        Long frameId = longValue(arguments.get("frameId"));
        Integer width = integerValue(arguments.get("width"));
        Integer height = integerValue(arguments.get("height"));
        String format = arguments.get("format") instanceof String
                ? (String) arguments.get("format")
                : null;
        Integer rotationDegrees = integerValue(arguments.get("rotationDegrees"));
        String cameraFacing = arguments.get("cameraFacing") instanceof String
                ? (String) arguments.get("cameraFacing")
                : "unknown";
        Object rawPlanes = arguments.get("planes");
        if (frameId == null
                || width == null
                || height == null
                || format == null
                || rotationDegrees == null
                || !(rawPlanes instanceof List<?>)) {
            throw new IllegalArgumentException("Incomplete camera frame metadata.");
        }

        List<DetectionModels.ImagePlane> planes = new ArrayList<>();
        for (Object rawPlane : (List<?>) rawPlanes) {
            Map<?, ?> plane = asMap(rawPlane);
            if (plane == null || !(plane.get("bytes") instanceof byte[])) {
                throw new IllegalArgumentException("Invalid camera plane.");
            }
            Integer bytesPerRow = integerValue(plane.get("bytesPerRow"));
            Integer bytesPerPixel = integerValue(plane.get("bytesPerPixel"));
            if (bytesPerRow == null || bytesPerRow <= 0) {
                throw new IllegalArgumentException("Camera row stride is required.");
            }
            planes.add(new DetectionModels.ImagePlane(
                    (byte[]) plane.get("bytes"),
                    bytesPerRow,
                    bytesPerPixel == null ? 1 : Math.max(1, bytesPerPixel)
            ));
        }
        return new DetectionModels.CameraFrame(
                frameId,
                width,
                height,
                format,
                rotationDegrees,
                cameraFacing,
                planes
        );
    }

    private File copyFlutterAssetToCache(String asset) throws IOException {
        File directory = new File(context.getCodeCacheDir(), "opencv_object_detection");
        if (!directory.exists() && !directory.mkdirs()) {
            throw new IOException("Could not create the OpenCV model cache directory.");
        }
        String safeName = asset.substring(asset.lastIndexOf('/') + 1)
                .replaceAll("[^A-Za-z0-9._-]", "_");
        long packageUpdate;
        try {
            packageUpdate = context.getPackageManager()
                    .getPackageInfo(context.getPackageName(), 0)
                    .lastUpdateTime;
        } catch (PackageManager.NameNotFoundException error) {
            throw new IOException("Could not resolve the installed app version.", error);
        }
        File destination = new File(directory, safeName + "." + packageUpdate);
        if (destination.isFile() && destination.length() > 0L) {
            return destination;
        }
        File temporary = new File(directory, safeName + "." + packageUpdate + ".tmp");
        if (temporary.exists() && !temporary.delete()) {
            throw new IOException("Could not clear the temporary OpenCV model cache.");
        }
        String assetPath = flutterAssets.getAssetFilePathByName(asset);
        try (InputStream input = context.getAssets().open(assetPath);
             FileOutputStream output = new FileOutputStream(temporary)) {
            AndroidIoUtils.copy(input, output);
        }
        if (destination.exists() && !destination.delete()) {
            throw new IOException("Could not replace the cached OpenCV model.");
        }
        if (!temporary.renameTo(destination)) {
            throw new IOException("Could not activate the cached OpenCV model.");
        }
        File[] cachedFiles = directory.listFiles();
        if (cachedFiles != null) {
            String versionedPrefix = safeName + ".";
            for (File cached : cachedFiles) {
                if (!cached.equals(destination)
                        && cached.getName().startsWith(versionedPrefix)
                        && !cached.getName().endsWith(".tmp")) {
                    // Best-effort cleanup; a stale file must not break startup.
                    //noinspection ResultOfMethodCallIgnored
                    cached.delete();
                }
            }
        }
        return destination;
    }

    private void submit(
            MethodChannel.Result result,
            String errorCode,
            ThrowingOperation operation
    ) {
        ExecutorService worker = executor;
        if (worker == null || worker.isShutdown()) {
            result.error("detached", "OpenCV object detector is detached.", null);
            return;
        }
        worker.execute(() -> {
            try {
                success(result, operation.run());
            } catch (Throwable error) {
                failure(result, errorCode, error);
            }
        });
    }

    private void success(MethodChannel.Result result, Object value) {
        mainHandler.post(() -> result.success(value));
    }

    private void failure(MethodChannel.Result result, String code, Throwable error) {
        Log.e(TAG, code + ": " + error.getMessage(), error);
        mainHandler.post(() -> result.error(
                code,
                error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage(),
                Log.getStackTraceString(error)
        ));
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        if (channel != null) channel.setMethodCallHandler(null);
        ExecutorService worker = executor;
        executor = null;
        if (worker != null && !worker.isShutdown()) {
            worker.execute(() -> {
                OpenCvObjectDetector currentDetector = detector;
                detector = null;
                if (currentDetector != null) currentDetector.close();
            });
            worker.shutdown();
        }
        channel = null;
        context = null;
        flutterAssets = null;
    }

    @SuppressWarnings("unchecked")
    private static Map<?, ?> asMap(Object value) {
        return value instanceof Map<?, ?> ? (Map<?, ?>) value : null;
    }

    private static Integer integerValue(Object value) {
        return value instanceof Number ? ((Number) value).intValue() : null;
    }

    private static Long longValue(Object value) {
        return value instanceof Number ? ((Number) value).longValue() : null;
    }

    private static Float floatValue(Object value) {
        return value instanceof Number ? ((Number) value).floatValue() : null;
    }

    private interface ThrowingOperation {
        Object run() throws Exception;
    }
}
