package com.grozziie.opencv_object_detection;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/** Stream helpers that remain compatible with the plugin's Android 24 minimum. */
final class AndroidIoUtils {
    private static final int BUFFER_SIZE = 16 * 1024;

    private AndroidIoUtils() {}

    static void copy(InputStream input, OutputStream output) throws IOException {
        byte[] buffer = new byte[BUFFER_SIZE];
        int count;
        while ((count = input.read(buffer)) != -1) {
            if (count == 0) continue;
            output.write(buffer, 0, count);
        }
    }

    static byte[] readAllBytes(InputStream input) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        copy(input, output);
        return output.toByteArray();
    }

    static byte[] readAllBytes(File file) throws IOException {
        try (InputStream input = new FileInputStream(file)) {
            return readAllBytes(input);
        }
    }
}
