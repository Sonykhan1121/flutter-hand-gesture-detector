package com.grozziie.opencv_object_detection;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import static org.junit.Assert.assertEquals;

public class UltralyticsMetadataReaderTest {
    @Rule
    public final TemporaryFolder temporaryFolder = new TemporaryFolder();

    @Test
    public void readsPythonMetadataFromAppendedZip() throws Exception {
        String metadata = "{'task': 'detect', 'imgsz': [256, 256], "
                + "'names': {0: 'Person', 1: 'Bottle opener'}}";
        File model = temporaryFolder.newFile("model.tflite");
        try (FileOutputStream output = new FileOutputStream(model)) {
            output.write(new byte[]{0x54, 0x46, 0x4c, 0x33});
            output.write(metadataZip(metadata));
        }

        DetectionModels.Metadata parsed = UltralyticsMetadataReader.read(model);

        assertEquals("detect", parsed.task);
        assertEquals(256, parsed.inputWidth);
        assertEquals(256, parsed.inputHeight);
        assertEquals(2, parsed.labels.size());
        assertEquals("Person", parsed.labels.get(0));
        assertEquals("Bottle opener", parsed.labels.get(1));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsNonContiguousClassIndexes() throws Exception {
        String metadata = "{'task': 'detect', 'imgsz': [256, 256], "
                + "'names': {0: 'Person', 2: 'Bottle'}}";
        File model = temporaryFolder.newFile("bad-model.tflite");
        try (FileOutputStream output = new FileOutputStream(model)) {
            output.write(metadataZip(metadata));
        }

        UltralyticsMetadataReader.read(model);
    }

    private byte[] metadataZip(String metadata) throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(bytes)) {
            zip.putNextEntry(new ZipEntry("temp_meta.txt"));
            zip.write(metadata.getBytes(StandardCharsets.UTF_8));
            zip.closeEntry();
        }
        return bytes.toByteArray();
    }
}
