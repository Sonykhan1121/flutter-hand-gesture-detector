package com.grozziie.opencv_object_detection;

import android.util.Log;

import org.opencv.core.Core;
import org.opencv.core.CvType;
import org.opencv.core.Mat;
import org.opencv.core.Scalar;
import org.opencv.core.Size;
import org.opencv.dnn.Dnn;
import org.opencv.dnn.Net;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** OpenCV Java DNN runner for the bundled 601-class YOLOv8 model. */
final class OpenCvObjectDetector implements AutoCloseable {
    private static final String TAG = "OpenCvObjectDetection";
    private static final int REQUIRED_INPUT_SIZE = 256;
    private static final int BOX_FEATURE_COUNT = 4;

    private final DetectionModels.Metadata metadata;
    private Net network;
    private final float confidenceThreshold;
    private final float iouThreshold;
    private final int maxResults;
    private final int[] outputDimensions;

    OpenCvObjectDetector(
            File modelFile,
            File metadataFile,
            float confidenceThreshold,
            float iouThreshold,
            int maxResults,
            int expectedClassCount
    ) throws IOException {
        this.confidenceThreshold = confidenceThreshold;
        this.iouThreshold = iouThreshold;
        this.maxResults = maxResults;
        metadata = UltralyticsMetadataReader.read(metadataFile);
        if (!metadata.task.equalsIgnoreCase("detect")) {
            throw new IllegalArgumentException(
                    "Expected an object-detection model but found task " + metadata.task + "."
            );
        }
        if (metadata.inputWidth != REQUIRED_INPUT_SIZE
                || metadata.inputHeight != REQUIRED_INPUT_SIZE) {
            throw new IllegalArgumentException(
                    "Expected a 256x256 model but found "
                            + metadata.inputWidth + "x" + metadata.inputHeight + "."
            );
        }
        if (metadata.labels.size() != expectedClassCount) {
            throw new IllegalArgumentException(
                    "Expected " + expectedClassCount + " model classes but found "
                            + metadata.labels.size() + "."
            );
        }

        if (!modelFile.getName().toLowerCase().endsWith(".onnx")) {
            throw new IllegalArgumentException(
                    "OpenCV SDK requires an ONNX model but received "
                            + modelFile.getName() + "."
            );
        }
        Net loaded = Dnn.readNetFromONNX(modelFile.getAbsolutePath());
        try {
            if (loaded.empty()) {
                throw new IllegalStateException("OpenCV returned an empty ONNX network.");
            }
            loaded.setPreferableBackend(Dnn.DNN_BACKEND_OPENCV);
            loaded.setPreferableTarget(Dnn.DNN_TARGET_CPU);
            outputDimensions = warmUpAndInspect(loaded);
            if (!YoloPostprocessor.hasSupportedLayout(
                    outputDimensions,
                    metadata.labels.size()
            )) {
                throw new IllegalArgumentException(
                        "OpenCV produced unsupported YOLO output "
                                + Arrays.toString(outputDimensions)
                                + "; expected "
                                + (metadata.labels.size() + BOX_FEATURE_COUNT)
                                + " features."
                );
            }
            network = loaded;
        } catch (RuntimeException | Error error) {
            throw error;
        }
        Log.i(
                TAG,
                "OpenCV DNN ready; version=" + Core.VERSION
                        + " input=" + metadata.inputWidth + "x" + metadata.inputHeight
                        + " format=ONNX"
                        + " output=" + Arrays.toString(outputDimensions)
                        + " classes=" + metadata.labels.size()
                        + " target=CPU"
        );
    }

    Map<String, Object> capabilities(boolean initialized) {
        Map<String, Object> values = new LinkedHashMap<>();
        values.put("platform", "android");
        values.put("initialized", initialized);
        values.put("opencvVersion", Core.VERSION);
        values.put("backend", "OpenCV DNN");
        values.put("target", "CPU");
        values.put("modelFormat", "ONNX");
        values.put("inputWidth", metadata.inputWidth);
        values.put("inputHeight", metadata.inputHeight);
        values.put("outputDimensions", integerList(outputDimensions));
        values.put("classCount", metadata.labels.size());
        return values;
    }

    Map<String, Object> detect(DetectionModels.CameraFrame frame) {
        long preprocessStart = System.nanoTime();
        try (DetectionModels.PreprocessedFrame preprocessed =
                     OpenCvFramePreprocessor.preprocess(
                             frame,
                             metadata.inputWidth,
                             metadata.inputHeight
                     )) {
            double preprocessMs = elapsedMilliseconds(preprocessStart);
            long inferenceStart = System.nanoTime();
            Net currentNetwork = network;
            if (currentNetwork == null) {
                throw new IllegalStateException("The OpenCV network is closed.");
            }
            currentNetwork.setInput(preprocessed.blob);
            Mat output = currentNetwork.forward();
            try {
                double inferenceMs = elapsedMilliseconds(inferenceStart);
                int[] actualDimensions = dimensions(output);
                if (!Arrays.equals(actualDimensions, outputDimensions)) {
                    throw new IllegalStateException(
                            "OpenCV output changed from " + Arrays.toString(outputDimensions)
                                    + " to " + Arrays.toString(actualDimensions) + "."
                    );
                }
                float[] values = floats(output);
                long postprocessStart = System.nanoTime();
                List<DetectionModels.Detection> detections = YoloPostprocessor.decode(
                        values,
                        actualDimensions,
                        metadata.labels,
                        preprocessed.transform,
                        confidenceThreshold,
                        iouThreshold,
                        maxResults
                );
                double postprocessMs = elapsedMilliseconds(postprocessStart);

                Map<String, Object> response = new LinkedHashMap<>();
                response.put("frameId", frame.frameId);
                response.put("imageWidth", preprocessed.uprightWidth);
                response.put("imageHeight", preprocessed.uprightHeight);
                response.put("rotationDegrees", frame.rotationDegrees);
                response.put("cameraFacing", frame.cameraFacing);
                response.put("coordinateSpace", "upright_unmirrored");
                response.put("preprocessMs", preprocessMs);
                response.put("inferenceMs", inferenceMs);
                response.put("postprocessMs", postprocessMs);
                response.put("backend", "OpenCV DNN");
                response.put("target", "CPU");
                response.put("detections", DetectionModels.detectionMaps(detections));
                return response;
            } finally {
                output.release();
            }
        }
    }

    private int[] warmUpAndInspect(Net loaded) {
        Mat image = new Mat(
                metadata.inputHeight,
                metadata.inputWidth,
                CvType.CV_8UC3,
                new Scalar(0, 0, 0)
        );
        Mat blob = Dnn.blobFromImage(
                image,
                1.0 / 255.0,
                new Size(metadata.inputWidth, metadata.inputHeight),
                new Scalar(0, 0, 0),
                true,
                false,
                CvType.CV_32F
        );
        try {
            loaded.setInput(blob);
            Mat output = loaded.forward();
            try {
                if (output.empty()) {
                    throw new IllegalStateException("OpenCV warm-up returned an empty tensor.");
                }
                floats(output);
                return dimensions(output);
            } finally {
                output.release();
            }
        } finally {
            blob.release();
            image.release();
        }
    }

    private static int[] dimensions(Mat mat) {
        int[] values = new int[mat.dims()];
        for (int index = 0; index < values.length; index++) {
            long dimension = mat.size(index);
            if (dimension <= 0 || dimension > Integer.MAX_VALUE) {
                throw new IllegalArgumentException("Invalid output tensor dimension " + dimension + ".");
            }
            values[index] = (int) dimension;
        }
        return values;
    }

    private static float[] floats(Mat mat) {
        if (mat.depth() != CvType.CV_32F) {
            throw new IllegalArgumentException(
                    "Expected a float32 output tensor but found OpenCV depth " + mat.depth() + "."
            );
        }
        long elementCount = mat.total() * mat.channels();
        if (elementCount <= 0 || elementCount > Integer.MAX_VALUE) {
            throw new IllegalArgumentException("Invalid output tensor element count " + elementCount + ".");
        }
        float[] values = new float[(int) elementCount];
        int[] origin = new int[mat.dims()];
        int copied = mat.get(origin, values);
        if (copied <= 0) {
            throw new IllegalStateException("OpenCV did not expose the output tensor values.");
        }
        return values;
    }

    private static List<Integer> integerList(int[] values) {
        List<Integer> result = new ArrayList<>(values.length);
        for (int value : values) result.add(value);
        return result;
    }

    private static double elapsedMilliseconds(long startedAtNanos) {
        return (System.nanoTime() - startedAtNanos) / 1_000_000.0;
    }

    @Override
    public void close() {
        // OpenCV's Java Net binding owns its native pointer through finalize()
        // and exposes no public release/clear method. Dropping the last strong
        // reference is the supported lifecycle boundary in this AAR.
        network = null;
    }
}
