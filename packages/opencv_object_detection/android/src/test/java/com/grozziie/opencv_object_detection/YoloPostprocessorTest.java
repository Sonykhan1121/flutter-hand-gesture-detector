package com.grozziie.opencv_object_detection;

import org.junit.Test;

import java.util.List;

import static org.junit.Assert.assertEquals;

public class YoloPostprocessorTest {
    @Test
    public void decodesChannelsFirstAndRemovesPerson() {
        float[] output = new float[]{
                128f, 64f,
                128f, 64f,
                100f, 20f,
                100f, 20f,
                0.1f, 0.95f,
                0.90f, 0.1f,
        };

        List<DetectionModels.Detection> detections = YoloPostprocessor.decode(
                output,
                new int[]{1, 6, 2},
                List.of("person", "Bottle"),
                transform(256, 256, 1f, 0f, 0f),
                0.25f,
                0.50f,
                5
        );

        assertEquals(1, detections.size());
        assertEquals("Bottle", detections.get(0).label);
        assertEquals(1, detections.get(0).classIndex);
        assertEquals(0.90f, detections.get(0).confidence, 0.0001f);
    }

    @Test
    public void reversesLetterboxingIntoNormalizedSourceCoordinates() {
        float[] output = new float[]{128f, 128f, 128f, 128f, 0.90f};

        List<DetectionModels.Detection> detections = YoloPostprocessor.decode(
                output,
                new int[]{1, 5, 1},
                List.of("Bottle"),
                transform(100, 200, 1.28f, 64f, 0f),
                0.25f,
                0.50f,
                5
        );

        DetectionModels.Detection detection = detections.get(0);
        assertEquals(0f, detection.left, 0.0001f);
        assertEquals(0.25f, detection.top, 0.0001f);
        assertEquals(1f, detection.right, 0.0001f);
        assertEquals(0.75f, detection.bottom, 0.0001f);
    }

    @Test
    public void appliesClassAwareNmsAndResultLimit() {
        float[] output = new float[]{
                128f, 130f,
                128f, 130f,
                100f, 100f,
                100f, 100f,
                0.90f, 0.80f,
        };

        List<DetectionModels.Detection> detections = YoloPostprocessor.decode(
                output,
                new int[]{1, 5, 2},
                List.of("Bottle"),
                transform(256, 256, 1f, 0f, 0f),
                0.25f,
                0.50f,
                1
        );

        assertEquals(1, detections.size());
        assertEquals(0.90f, detections.get(0).confidence, 0.0001f);
    }

    @Test
    public void keepsOverlappingBoxesFromDifferentClasses() {
        float[] output = new float[]{
                128f, 128f,
                128f, 128f,
                100f, 100f,
                100f, 100f,
                0.90f, 0.10f,
                0.10f, 0.80f,
        };

        List<DetectionModels.Detection> detections = YoloPostprocessor.decode(
                output,
                new int[]{1, 6, 2},
                List.of("Bottle", "Chair"),
                transform(256, 256, 1f, 0f, 0f),
                0.25f,
                0.50f,
                5
        );

        assertEquals(2, detections.size());
        assertEquals("Bottle", detections.get(0).label);
        assertEquals("Chair", detections.get(1).label);
    }

    @Test
    public void removesCandidatesBelowConfidenceThreshold() {
        float[] output = new float[]{128f, 128f, 100f, 100f, 0.24f};

        List<DetectionModels.Detection> detections = YoloPostprocessor.decode(
                output,
                new int[]{1, 5, 1},
                List.of("Bottle"),
                transform(256, 256, 1f, 0f, 0f),
                0.25f,
                0.50f,
                5
        );

        assertEquals(0, detections.size());
    }

    private DetectionModels.LetterboxTransform transform(
            int sourceWidth,
            int sourceHeight,
            float scale,
            float padX,
            float padY
    ) {
        return new DetectionModels.LetterboxTransform(
                sourceWidth,
                sourceHeight,
                256,
                256,
                scale,
                padX,
                padY
        );
    }
}
