package com.grozziie.opencv_object_detection;

import org.junit.Test;

import java.util.List;

import static org.junit.Assert.assertArrayEquals;

public class OpenCvFramePreprocessorTest {
    @Test
    public void reportsUprightDimensionsForEverySupportedRotation() {
        assertArrayEquals(
                new int[]{640, 480},
                OpenCvFramePreprocessor.uprightDimensions(640, 480, 0)
        );
        assertArrayEquals(
                new int[]{480, 640},
                OpenCvFramePreprocessor.uprightDimensions(640, 480, 90)
        );
        assertArrayEquals(
                new int[]{640, 480},
                OpenCvFramePreprocessor.uprightDimensions(640, 480, 180)
        );
        assertArrayEquals(
                new int[]{480, 640},
                OpenCvFramePreprocessor.uprightDimensions(640, 480, 270)
        );
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsUnsupportedRotation() {
        OpenCvFramePreprocessor.validate(yuv420Frame(45), 256, 256);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsIncompleteYuv420Frame() {
        DetectionModels.CameraFrame frame = new DetectionModels.CameraFrame(
                1,
                2,
                2,
                "yuv420",
                0,
                "front",
                List.of(new DetectionModels.ImagePlane(new byte[4], 2, 1))
        );

        OpenCvFramePreprocessor.validate(frame, 256, 256);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsUnsupportedFrameFormat() {
        DetectionModels.CameraFrame frame = new DetectionModels.CameraFrame(
                1,
                2,
                2,
                "bgra8888",
                0,
                "front",
                List.of(new DetectionModels.ImagePlane(new byte[16], 8, 4))
        );

        OpenCvFramePreprocessor.validate(frame, 256, 256);
    }

    @Test
    public void acceptsCompleteYuv420AndPackedNv21Frames() {
        OpenCvFramePreprocessor.validate(yuv420Frame(0), 256, 256);
        DetectionModels.CameraFrame nv21 = new DetectionModels.CameraFrame(
                2,
                2,
                2,
                "nv21",
                270,
                "back",
                List.of(new DetectionModels.ImagePlane(new byte[6], 2, 1))
        );

        OpenCvFramePreprocessor.validate(nv21, 256, 256);
    }

    @Test
    public void convertsStridedYuv420ToBgrWithoutChangingPixelOrder() {
        DetectionModels.CameraFrame frame = new DetectionModels.CameraFrame(
                3,
                2,
                2,
                "yuv420",
                0,
                "back",
                List.of(
                        new DetectionModels.ImagePlane(
                                new byte[]{16, (byte) 235, 0, 0, 81, (byte) 145, 0, 0},
                                4,
                                1
                        ),
                        new DetectionModels.ImagePlane(new byte[]{(byte) 128, 0}, 2, 1),
                        new DetectionModels.ImagePlane(new byte[]{(byte) 128, 0}, 2, 1)
                )
        );

        assertArrayEquals(
                new byte[]{
                        0, 0, 0,
                        (byte) 255, (byte) 255, (byte) 255,
                        76, 76, 76,
                        (byte) 150, (byte) 150, (byte) 150,
                },
                OpenCvFramePreprocessor.toBgr(frame)
        );
    }

    @Test
    public void convertsPackedNv21ToBgr() {
        DetectionModels.CameraFrame frame = new DetectionModels.CameraFrame(
                4,
                2,
                2,
                "nv21",
                0,
                "back",
                List.of(new DetectionModels.ImagePlane(
                        new byte[]{16, (byte) 235, 81, (byte) 145, (byte) 128, (byte) 128},
                        2,
                        1
                ))
        );

        assertArrayEquals(
                new byte[]{
                        0, 0, 0,
                        (byte) 255, (byte) 255, (byte) 255,
                        76, 76, 76,
                        (byte) 150, (byte) 150, (byte) 150,
                },
                OpenCvFramePreprocessor.toBgr(frame)
        );
    }

    private DetectionModels.CameraFrame yuv420Frame(int rotation) {
        return new DetectionModels.CameraFrame(
                1,
                2,
                2,
                "yuv420",
                rotation,
                "front",
                List.of(
                        new DetectionModels.ImagePlane(new byte[4], 2, 1),
                        new DetectionModels.ImagePlane(new byte[1], 1, 1),
                        new DetectionModels.ImagePlane(new byte[1], 1, 1)
                )
        );
    }
}
