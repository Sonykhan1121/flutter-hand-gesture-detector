package com.grozziie.opencv_object_detection;

import org.opencv.core.Mat;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

final class DetectionModels {
    private DetectionModels() {}

    static final class ImagePlane {
        final byte[] bytes;
        final int bytesPerRow;
        final int bytesPerPixel;

        ImagePlane(byte[] bytes, int bytesPerRow, int bytesPerPixel) {
            this.bytes = bytes;
            this.bytesPerRow = bytesPerRow;
            this.bytesPerPixel = bytesPerPixel;
        }
    }

    static final class CameraFrame {
        final long frameId;
        final int width;
        final int height;
        final String format;
        final int rotationDegrees;
        final String cameraFacing;
        final List<ImagePlane> planes;

        CameraFrame(
                long frameId,
                int width,
                int height,
                String format,
                int rotationDegrees,
                String cameraFacing,
                List<ImagePlane> planes
        ) {
            this.frameId = frameId;
            this.width = width;
            this.height = height;
            this.format = format;
            this.rotationDegrees = rotationDegrees;
            this.cameraFacing = cameraFacing;
            this.planes = planes;
        }
    }

    static final class Metadata {
        final String task;
        final int inputWidth;
        final int inputHeight;
        final List<String> labels;

        Metadata(String task, int inputWidth, int inputHeight, List<String> labels) {
            this.task = task;
            this.inputWidth = inputWidth;
            this.inputHeight = inputHeight;
            this.labels = Collections.unmodifiableList(new ArrayList<>(labels));
        }
    }

    static final class LetterboxTransform {
        final int sourceWidth;
        final int sourceHeight;
        final int modelWidth;
        final int modelHeight;
        final float scale;
        final float padX;
        final float padY;

        LetterboxTransform(
                int sourceWidth,
                int sourceHeight,
                int modelWidth,
                int modelHeight,
                float scale,
                float padX,
                float padY
        ) {
            this.sourceWidth = sourceWidth;
            this.sourceHeight = sourceHeight;
            this.modelWidth = modelWidth;
            this.modelHeight = modelHeight;
            this.scale = scale;
            this.padX = padX;
            this.padY = padY;
        }
    }

    static final class PreprocessedFrame implements AutoCloseable {
        final Mat blob;
        final int uprightWidth;
        final int uprightHeight;
        final LetterboxTransform transform;

        PreprocessedFrame(
                Mat blob,
                int uprightWidth,
                int uprightHeight,
                LetterboxTransform transform
        ) {
            this.blob = blob;
            this.uprightWidth = uprightWidth;
            this.uprightHeight = uprightHeight;
            this.transform = transform;
        }

        @Override
        public void close() {
            blob.release();
        }
    }

    static final class Detection {
        final float left;
        final float top;
        final float right;
        final float bottom;
        final String label;
        final int classIndex;
        final float confidence;

        Detection(
                float left,
                float top,
                float right,
                float bottom,
                String label,
                int classIndex,
                float confidence
        ) {
            this.left = left;
            this.top = top;
            this.right = right;
            this.bottom = bottom;
            this.label = label;
            this.classIndex = classIndex;
            this.confidence = confidence;
        }

        Map<String, Object> asMap() {
            Map<String, Object> value = new LinkedHashMap<>();
            value.put("left", (double) left);
            value.put("top", (double) top);
            value.put("right", (double) right);
            value.put("bottom", (double) bottom);
            value.put("label", label);
            value.put("classIndex", classIndex);
            value.put("confidence", (double) confidence);
            value.put("trackingId", null);
            return value;
        }
    }

    static List<Map<String, Object>> detectionMaps(List<Detection> detections) {
        List<Map<String, Object>> values = new ArrayList<>(detections.size());
        for (Detection detection : detections) {
            values.add(detection.asMap());
        }
        return values;
    }
}
