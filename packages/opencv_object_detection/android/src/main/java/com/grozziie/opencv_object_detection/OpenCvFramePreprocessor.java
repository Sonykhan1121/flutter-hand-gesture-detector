package com.grozziie.opencv_object_detection;

import org.opencv.core.Core;
import org.opencv.core.CvType;
import org.opencv.core.Mat;
import org.opencv.core.Scalar;
import org.opencv.core.Size;
import org.opencv.dnn.Dnn;
import org.opencv.imgproc.Imgproc;

/** Converts camera-plugin YUV planes into an upright, letterboxed OpenCV blob. */
final class OpenCvFramePreprocessor {
    private OpenCvFramePreprocessor() {}

    static DetectionModels.PreprocessedFrame preprocess(
            DetectionModels.CameraFrame frame,
            int modelWidth,
            int modelHeight
    ) {
        validate(frame, modelWidth, modelHeight);
        byte[] bgrBytes = toBgr(frame);
        Mat raw = new Mat(frame.height, frame.width, CvType.CV_8UC3);
        Mat upright = new Mat();
        Mat resized = new Mat();
        Mat letterboxed = new Mat();
        try {
            raw.put(0, 0, bgrBytes);
            rotate(raw, upright, frame.rotationDegrees);
            int[] expectedUprightDimensions = uprightDimensions(
                    frame.width,
                    frame.height,
                    frame.rotationDegrees
            );
            if (upright.cols() != expectedUprightDimensions[0]
                    || upright.rows() != expectedUprightDimensions[1]) {
                throw new IllegalStateException(
                        "OpenCV produced unexpected upright frame dimensions."
                );
            }

            float scale = Math.min(
                    (float) modelWidth / upright.cols(),
                    (float) modelHeight / upright.rows()
            );
            int resizedWidth = Math.max(1, Math.round(upright.cols() * scale));
            int resizedHeight = Math.max(1, Math.round(upright.rows() * scale));
            int left = (modelWidth - resizedWidth) / 2;
            int right = modelWidth - resizedWidth - left;
            int top = (modelHeight - resizedHeight) / 2;
            int bottom = modelHeight - resizedHeight - top;

            Imgproc.resize(
                    upright,
                    resized,
                    new Size(resizedWidth, resizedHeight),
                    0,
                    0,
                    Imgproc.INTER_LINEAR
            );
            Core.copyMakeBorder(
                    resized,
                    letterboxed,
                    top,
                    bottom,
                    left,
                    right,
                    Core.BORDER_CONSTANT,
                    new Scalar(114, 114, 114)
            );
            Mat blob = Dnn.blobFromImage(
                    letterboxed,
                    1.0 / 255.0,
                    new Size(modelWidth, modelHeight),
                    new Scalar(0, 0, 0),
                    true,
                    false,
                    CvType.CV_32F
            );
            DetectionModels.LetterboxTransform transform =
                    new DetectionModels.LetterboxTransform(
                            upright.cols(),
                            upright.rows(),
                            modelWidth,
                            modelHeight,
                            scale,
                            left,
                            top
                    );
            return new DetectionModels.PreprocessedFrame(
                    blob,
                    upright.cols(),
                    upright.rows(),
                    transform
            );
        } finally {
            letterboxed.release();
            resized.release();
            upright.release();
            raw.release();
        }
    }

    static void validate(
            DetectionModels.CameraFrame frame,
            int modelWidth,
            int modelHeight
    ) {
        if (frame.width <= 0 || frame.height <= 0) {
            throw new IllegalArgumentException("Invalid camera dimensions.");
        }
        if (modelWidth <= 0 || modelHeight <= 0) {
            throw new IllegalArgumentException("Invalid model dimensions.");
        }
        if (frame.rotationDegrees != 0
                && frame.rotationDegrees != 90
                && frame.rotationDegrees != 180
                && frame.rotationDegrees != 270) {
            throw new IllegalArgumentException(
                    "Unsupported frame rotation " + frame.rotationDegrees + "."
            );
        }
        if (frame.format.equalsIgnoreCase("yuv420")) {
            if (frame.planes.size() < 3) {
                throw new IllegalArgumentException("YUV420 frames require Y, U, and V planes.");
            }
        } else if (frame.format.equalsIgnoreCase("nv21")) {
            if (frame.planes.isEmpty()) {
                throw new IllegalArgumentException("NV21 frames require one packed plane.");
            }
        } else {
            throw new IllegalArgumentException(
                    "Unsupported Android camera format: " + frame.format + "."
            );
        }
    }

    static int[] uprightDimensions(int width, int height, int rotationDegrees) {
        if (rotationDegrees != 0
                && rotationDegrees != 90
                && rotationDegrees != 180
                && rotationDegrees != 270) {
            throw new IllegalArgumentException(
                    "Unsupported frame rotation " + rotationDegrees + "."
            );
        }
        return rotationDegrees == 90 || rotationDegrees == 270
                ? new int[]{height, width}
                : new int[]{width, height};
    }

    static byte[] toBgr(DetectionModels.CameraFrame frame) {
        byte[] output = new byte[frame.width * frame.height * 3];
        boolean isNv21 = frame.format.equalsIgnoreCase("nv21");
        DetectionModels.ImagePlane packedPlane = isNv21 ? frame.planes.get(0) : null;
        DetectionModels.ImagePlane yPlane = isNv21 ? null : frame.planes.get(0);
        DetectionModels.ImagePlane uPlane = isNv21 ? null : frame.planes.get(1);
        DetectionModels.ImagePlane vPlane = isNv21 ? null : frame.planes.get(2);
        for (int y = 0; y < frame.height; y++) {
            for (int x = 0; x < frame.width; x++) {
                int yValue;
                int uValue;
                int vValue;
                if (isNv21) {
                    int yIndex = y * packedPlane.bytesPerRow + x;
                    int chromaStart = packedPlane.bytesPerRow * frame.height;
                    int chromaIndex = chromaStart
                            + (y / 2) * packedPlane.bytesPerRow
                            + (x / 2) * 2;
                    yValue = byteValue(packedPlane.bytes, yIndex, 16);
                    uValue = byteValue(packedPlane.bytes, chromaIndex + 1, 128);
                    vValue = byteValue(packedPlane.bytes, chromaIndex, 128);
                } else {
                    yValue = planeValue(yPlane, x, y, 16);
                    uValue = planeValue(uPlane, x / 2, y / 2, 128);
                    vValue = planeValue(vPlane, x / 2, y / 2, 128);
                }
                float yf = Math.max(0f, yValue - 16f);
                float uf = uValue - 128f;
                float vf = vValue - 128f;
                int red = clamp(Math.round(1.164f * yf + 1.596f * vf));
                int green = clamp(Math.round(1.164f * yf - 0.392f * uf - 0.813f * vf));
                int blue = clamp(Math.round(1.164f * yf + 2.017f * uf));
                int index = (y * frame.width + x) * 3;
                output[index] = (byte) blue;
                output[index + 1] = (byte) green;
                output[index + 2] = (byte) red;
            }
        }
        return output;
    }

    private static int planeValue(
            DetectionModels.ImagePlane plane,
            int x,
            int y,
            int fallback
    ) {
        int index = y * plane.bytesPerRow + x * Math.max(1, plane.bytesPerPixel);
        return byteValue(plane.bytes, index, fallback);
    }

    private static int byteValue(byte[] bytes, int index, int fallback) {
        if (index < 0 || index >= bytes.length) return fallback;
        return bytes[index] & 0xff;
    }

    private static int clamp(int value) {
        return Math.max(0, Math.min(255, value));
    }

    private static void rotate(Mat source, Mat destination, int rotationDegrees) {
        switch (rotationDegrees) {
            case 90 -> Core.rotate(source, destination, Core.ROTATE_90_CLOCKWISE);
            case 180 -> Core.rotate(source, destination, Core.ROTATE_180);
            case 270 -> Core.rotate(source, destination, Core.ROTATE_90_COUNTERCLOCKWISE);
            default -> source.copyTo(destination);
        }
    }
}
