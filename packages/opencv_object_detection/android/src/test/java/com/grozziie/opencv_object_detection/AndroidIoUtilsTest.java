package com.grozziie.opencv_object_detection;

import org.junit.Test;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

import static org.junit.Assert.assertArrayEquals;

public class AndroidIoUtilsTest {
    @Test
    public void copiesAnInputStreamWithoutJavaNineApis() throws Exception {
        byte[] expected = "OpenCV model bytes".getBytes(StandardCharsets.UTF_8);
        ByteArrayOutputStream output = new ByteArrayOutputStream();

        AndroidIoUtils.copy(new ByteArrayInputStream(expected), output);

        assertArrayEquals(expected, output.toByteArray());
    }

    @Test
    public void readsAllFileBytesWithoutJavaNioFiles() throws Exception {
        byte[] expected = new byte[40_000];
        for (int index = 0; index < expected.length; index++) {
            expected[index] = (byte) (index % 251);
        }
        File file = File.createTempFile("opencv-android-io", ".bin");
        try {
            try (FileOutputStream output = new FileOutputStream(file)) {
                output.write(expected);
            }

            assertArrayEquals(expected, AndroidIoUtils.readAllBytes(file));
        } finally {
            file.delete();
        }
    }
}
