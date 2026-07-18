package com.grozziie.opencv_object_detection;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/** Reads the metadata archive appended by Ultralytics to exported TFLite models. */
final class UltralyticsMetadataReader {
    private static final int LOCAL_HEADER_MINIMUM_SIZE = 30;
    private static final List<String> METADATA_NAMES = Arrays.asList(
            "metadata.json",
            "TFLITE_ULTRALYTICS_METADATA.json",
            "temp_meta.txt"
    );
    private static final Pattern TASK = Pattern.compile(
            "[\\\"']task[\\\"']\\s*:\\s*[\\\"']([^\\\"']+)[\\\"']"
    );
    private static final Pattern IMAGE_SIZE = Pattern.compile(
            "[\\\"']imgsz[\\\"']\\s*:\\s*\\[\\s*(\\d+)\\s*,\\s*(\\d+)\\s*]"
    );
    private static final Pattern SINGLE_QUOTED_LABEL = Pattern.compile(
            "(\\d+)\\s*:\\s*'((?:\\\\.|[^'])*)'"
    );
    private static final Pattern DOUBLE_QUOTED_LABEL = Pattern.compile(
            "[\\\"]?(\\d+)[\\\"]?\\s*:\\s*\\\"((?:\\\\.|[^\\\"])*)\\\""
    );

    private UltralyticsMetadataReader() {}

    static DetectionModels.Metadata read(File modelFile) throws IOException {
        String text = readMetadataText(AndroidIoUtils.readAllBytes(modelFile));
        Matcher taskMatcher = TASK.matcher(text);
        if (!taskMatcher.find()) {
            throw new IllegalArgumentException("The model metadata has no task.");
        }
        Matcher sizeMatcher = IMAGE_SIZE.matcher(text);
        if (!sizeMatcher.find()) {
            throw new IllegalArgumentException("The model metadata has no image size.");
        }

        int inputHeight = Integer.parseInt(sizeMatcher.group(1));
        int inputWidth = Integer.parseInt(sizeMatcher.group(2));
        List<String> labels = readLabels(text);
        return new DetectionModels.Metadata(
                taskMatcher.group(1).trim(),
                inputWidth,
                inputHeight,
                labels
        );
    }

    static String readMetadataText(byte[] modelBytes) throws IOException {
        int offset = findMetadataLocalHeader(modelBytes);
        try (ZipInputStream zip = new ZipInputStream(
                new ByteArrayInputStream(modelBytes, offset, modelBytes.length - offset),
                StandardCharsets.UTF_8
        )) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                if (METADATA_NAMES.contains(entry.getName())) {
                    return new String(
                            AndroidIoUtils.readAllBytes(zip),
                            StandardCharsets.UTF_8
                    );
                }
            }
        }
        throw new IllegalArgumentException("The model has no readable metadata entry.");
    }

    private static List<String> readLabels(String metadata) {
        int namesStart = Math.max(
                metadata.indexOf("'names':"),
                metadata.indexOf("\"names\":")
        );
        if (namesStart < 0) {
            throw new IllegalArgumentException("The model metadata has no class names.");
        }
        String namesText = metadata.substring(namesStart);
        TreeMap<Integer, String> labels = new TreeMap<>();
        collectLabels(SINGLE_QUOTED_LABEL.matcher(namesText), labels);
        collectLabels(DOUBLE_QUOTED_LABEL.matcher(namesText), labels);
        if (labels.isEmpty()) {
            throw new IllegalArgumentException("The model class list is empty.");
        }

        List<String> result = new ArrayList<>(labels.size());
        for (int index = 0; index < labels.size(); index++) {
            String label = labels.get(index);
            if (label == null || label.trim().isEmpty()) {
                throw new IllegalArgumentException(
                        "The model class indexes must be contiguous and start at zero."
                );
            }
            result.add(label.trim());
        }
        return result;
    }

    private static void collectLabels(Matcher matcher, Map<Integer, String> labels) {
        while (matcher.find()) {
            int index = Integer.parseInt(matcher.group(1));
            labels.putIfAbsent(index, decodeEscapes(matcher.group(2)).trim());
        }
    }

    private static String decodeEscapes(String value) {
        StringBuilder decoded = new StringBuilder(value.length());
        boolean escaping = false;
        for (int index = 0; index < value.length(); index++) {
            char current = value.charAt(index);
            if (!escaping && current == '\\') {
                escaping = true;
                continue;
            }
            if (escaping) {
                switch (current) {
                    case 'n' -> decoded.append('\n');
                    case 'r' -> decoded.append('\r');
                    case 't' -> decoded.append('\t');
                    default -> decoded.append(current);
                }
                escaping = false;
            } else {
                decoded.append(current);
            }
        }
        if (escaping) decoded.append('\\');
        return decoded.toString();
    }

    private static int findMetadataLocalHeader(byte[] bytes) {
        for (int offset = 0; offset <= bytes.length - LOCAL_HEADER_MINIMUM_SIZE; offset++) {
            if (!hasLocalHeaderSignature(bytes, offset)) continue;
            int nameLength = littleEndianUnsignedShort(bytes, offset + 26);
            int nameStart = offset + LOCAL_HEADER_MINIMUM_SIZE;
            int nameEnd = nameStart + nameLength;
            if (nameEnd > bytes.length) continue;
            String name = new String(bytes, nameStart, nameLength, StandardCharsets.UTF_8);
            if (METADATA_NAMES.contains(name)) return offset;
        }
        throw new IllegalArgumentException("The model has no appended Ultralytics metadata ZIP.");
    }

    private static boolean hasLocalHeaderSignature(byte[] bytes, int offset) {
        return bytes[offset] == 0x50
                && bytes[offset + 1] == 0x4b
                && bytes[offset + 2] == 0x03
                && bytes[offset + 3] == 0x04;
    }

    private static int littleEndianUnsignedShort(byte[] bytes, int offset) {
        return (bytes[offset] & 0xff) | ((bytes[offset + 1] & 0xff) << 8);
    }
}
