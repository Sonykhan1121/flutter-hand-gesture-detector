package com.grozziie.native_object_detection

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class ModelMetadataReaderTest {
    @Test
    fun `reads metadata ZIP appended after TFLite bytes`() {
        val metadata = """{"names":{"0":"person","1":"bottle"}}"""
        val appendedZip = ByteArrayOutputStream().also { output ->
            ZipOutputStream(output).use { zip ->
                zip.putNextEntry(ZipEntry("metadata.json"))
                zip.write(metadata.toByteArray())
                zip.closeEntry()
            }
        }.toByteArray()
        val model = File.createTempFile("prefixed-model", ".tflite")
        try {
            model.writeBytes(
                byteArrayOf(0x54, 0x46, 0x4c, 0x33, 0x00, 0x01) + appendedZip,
            )

            assertEquals(
                metadata,
                ModelMetadataReader.readMetadataJson(model.readBytes()),
            )
        } finally {
            model.delete()
        }
    }

    @Test
    fun `reads contiguous labels from legacy Ultralytics temp metadata`() {
        val metadata = """{'task': 'detect', 'names': {0: 'Accordion', 1: "Women's bag", 2: 'Zucchini'}}"""
        val appendedZip = ByteArrayOutputStream().also { output ->
            ZipOutputStream(output).use { zip ->
                zip.putNextEntry(ZipEntry("temp_meta.txt"))
                zip.write(metadata.toByteArray())
                zip.closeEntry()
            }
        }.toByteArray()
        val model = File.createTempFile("legacy-model", ".tflite")
        try {
            model.writeBytes(
                byteArrayOf(0x54, 0x46, 0x4c, 0x33, 0x00, 0x01) + appendedZip,
            )

            assertEquals(
                listOf("Accordion", "Women's bag", "Zucchini"),
                ModelMetadataReader.readLabels(model),
            )
        } finally {
            model.delete()
        }
    }
}
