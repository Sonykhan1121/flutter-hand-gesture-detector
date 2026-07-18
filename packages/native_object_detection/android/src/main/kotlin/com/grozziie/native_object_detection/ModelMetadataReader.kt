package com.grozziie.native_object_detection

import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.util.zip.ZipInputStream

/** Reads the Ultralytics metadata ZIP appended to a TFLite model. */
internal object ModelMetadataReader {
    fun readLabels(modelFile: File): List<String> {
        val metadata = readMetadataText(modelFile.readBytes())
        return runCatching { readJsonLabels(metadata) }
            .getOrElse { readPythonDictionaryLabels(metadata) }
    }

    private fun readJsonLabels(metadata: String): List<String> {
        val names = JSONObject(metadata).optJSONObject("names")
            ?: error("The model metadata has no JSON class names.")
        return validateLabels(
            names.keys().asSequence()
            .mapNotNull { key -> key.toIntOrNull()?.let { it to names.optString(key) } }
            .toList(),
        )
    }

    /** Parses the Python dictionary stored as temp_meta.txt by older exports. */
    private fun readPythonDictionaryLabels(metadata: String): List<String> {
        val namesStart = metadata.indexOf("'names':")
        require(namesStart >= 0) { "The model metadata has no class names." }
        val namesMetadata = metadata.substring(namesStart)
        val entries = buildList {
            addAll(singleQuotedLabel.findAll(namesMetadata).map(::labelEntry))
            addAll(doubleQuotedLabel.findAll(namesMetadata).map(::labelEntry))
        }
        return validateLabels(entries)
    }

    private fun labelEntry(match: MatchResult): Pair<Int, String> {
        return match.groupValues[1].toInt() to
            decodePythonString(match.groupValues[2])
    }

    private fun decodePythonString(value: String): String {
        val decoded = StringBuilder(value.length)
        var index = 0
        while (index < value.length) {
            val current = value[index++]
            if (current != '\\' || index >= value.length) {
                decoded.append(current)
                continue
            }
            when (val escaped = value[index++]) {
                'n' -> decoded.append('\n')
                'r' -> decoded.append('\r')
                't' -> decoded.append('\t')
                '\\', '\'', '"' -> decoded.append(escaped)
                else -> decoded.append(escaped)
            }
        }
        return decoded.toString()
    }

    private fun validateLabels(entries: List<Pair<Int, String>>): List<String> {
        val sorted = entries
            .map { it.first to it.second.trim() }
            .filter { it.second.isNotEmpty() }
            .distinctBy { it.first }
            .sortedBy { it.first }
        require(sorted.isNotEmpty()) { "The model class list is empty." }
        require(sorted.indices.all { sorted[it].first == it }) {
            "The model class indexes must be contiguous and start at zero."
        }
        return sorted.map { it.second }
    }

    /**
     * Ultralytics appends a complete ZIP after the TFLite flatbuffer. Android's
     * ZipFile interprets its relative local-header offsets from byte zero and
     * therefore rejects this valid self-extracting layout. Start ZipInputStream
     * at the metadata entry's real local header instead.
     */
    internal fun readMetadataJson(modelBytes: ByteArray): String {
        return readMetadataText(modelBytes)
    }

    private fun readMetadataText(modelBytes: ByteArray): String {
        val zipOffset = findMetadataLocalHeader(modelBytes)
        ZipInputStream(
            ByteArrayInputStream(modelBytes, zipOffset, modelBytes.size - zipOffset),
        ).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                if (entry.name in metadataEntryNames) {
                    return zip.bufferedReader().use { it.readText() }
                }
                zip.closeEntry()
                entry = zip.nextEntry
            }
        }
        error("The model has no readable Ultralytics metadata JSON.")
    }

    private fun findMetadataLocalHeader(bytes: ByteArray): Int {
        var offset = 0
        while (offset <= bytes.size - localHeaderMinimumSize) {
            if (hasLocalHeaderSignature(bytes, offset)) {
                val nameLength = littleEndianUnsignedShort(bytes, offset + 26)
                val nameStart = offset + localHeaderMinimumSize
                val nameEnd = nameStart + nameLength
                if (nameEnd <= bytes.size) {
                    val name = bytes.decodeToString(nameStart, nameEnd)
                    if (name in metadataEntryNames) return offset
                }
            }
            offset++
        }
        error("The model has no appended Ultralytics metadata ZIP.")
    }

    private fun hasLocalHeaderSignature(bytes: ByteArray, offset: Int): Boolean {
        return bytes[offset] == 0x50.toByte() &&
            bytes[offset + 1] == 0x4b.toByte() &&
            bytes[offset + 2] == 0x03.toByte() &&
            bytes[offset + 3] == 0x04.toByte()
    }

    private fun littleEndianUnsignedShort(bytes: ByteArray, offset: Int): Int {
        return (bytes[offset].toInt() and 0xff) or
            ((bytes[offset + 1].toInt() and 0xff) shl 8)
    }

    private const val localHeaderMinimumSize = 30
    private val metadataEntryNames = setOf(
        "metadata.json",
        "TFLITE_ULTRALYTICS_METADATA.json",
        "temp_meta.txt",
    )

    private val singleQuotedLabel =
        Regex("""(\d+)\s*:\s*'((?:\\.|[^'])*)'""")
    private val doubleQuotedLabel =
        Regex("""(\d+)\s*:\s*"((?:\\.|[^"])*)"""")
}
