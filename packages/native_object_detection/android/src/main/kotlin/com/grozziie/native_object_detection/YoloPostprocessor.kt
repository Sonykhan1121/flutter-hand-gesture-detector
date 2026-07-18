package com.grozziie.native_object_detection

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** Pure-Kotlin YOLO decoding and class-aware non-maximum suppression. */
internal object YoloPostprocessor {
    private data class Candidate(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
        val classIndex: Int,
        val confidence: Float,
    )

    fun decode(
        output: FloatArray,
        outputDimensions: IntArray,
        labels: List<String>,
        transform: LetterboxTransform,
        confidenceThreshold: Float,
        iouThreshold: Float,
        maxResults: Int,
    ): List<NativeDetection> {
        if (output.isEmpty() || labels.isEmpty() || maxResults <= 0) return emptyList()

        val features = labels.size + 4
        val dimensions = outputDimensions.filter { it > 0 }
        val last = dimensions.lastOrNull() ?: 0
        val secondLast = dimensions.getOrNull(dimensions.lastIndex - 1) ?: 0
        val candidates = when {
            secondLast > 0 && last == 6 && output.size >= secondLast * last ->
                decodeEndToEnd(
                    output,
                    rowCount = secondLast,
                    rowLength = last,
                    transform = transform,
                    labels = labels,
                    confidenceThreshold = confidenceThreshold,
                )
            secondLast == features && last > 0 -> decodeRaw(
                output,
                anchorCount = last,
                featureCount = secondLast,
                channelsFirst = true,
                transform = transform,
                labels = labels,
                confidenceThreshold = confidenceThreshold,
            )
            last == features && secondLast > 0 -> decodeRaw(
                output,
                anchorCount = secondLast,
                featureCount = last,
                channelsFirst = false,
                transform = transform,
                labels = labels,
                confidenceThreshold = confidenceThreshold,
            )
            output.size % features == 0 -> decodeRaw(
                output,
                anchorCount = output.size / features,
                featureCount = features,
                channelsFirst = true,
                transform = transform,
                labels = labels,
                confidenceThreshold = confidenceThreshold,
            )
            else -> emptyList()
        }

        val kept = classAwareNms(
            candidates.sortedByDescending { it.confidence },
            iouThreshold,
            maxResults,
        )
        return kept.map { candidate ->
            NativeDetection(
                left = candidate.left,
                top = candidate.top,
                right = candidate.right,
                bottom = candidate.bottom,
                label = labels.getOrElse(candidate.classIndex) {
                    "class ${candidate.classIndex}"
                },
                classIndex = candidate.classIndex,
                confidence = candidate.confidence,
            )
        }
    }

    private fun decodeRaw(
        output: FloatArray,
        anchorCount: Int,
        featureCount: Int,
        channelsFirst: Boolean,
        transform: LetterboxTransform,
        labels: List<String>,
        confidenceThreshold: Float,
    ): List<Candidate> {
        val candidates = ArrayList<Candidate>()
        fun value(anchor: Int, feature: Int): Float {
            val index = if (channelsFirst) {
                feature * anchorCount + anchor
            } else {
                anchor * featureCount + feature
            }
            return output.getOrElse(index) { Float.NaN }
        }

        for (anchor in 0 until anchorCount) {
            var classIndex = -1
            var confidence = Float.NEGATIVE_INFINITY
            for (classOffset in labels.indices) {
                val score = value(anchor, classOffset + 4)
                if (score.isFinite() && score > confidence) {
                    confidence = score
                    classIndex = classOffset
                }
            }
            if (classIndex < 0 ||
                confidence < confidenceThreshold ||
                isPerson(classIndex, labels)
            ) {
                continue
            }

            var centerX = value(anchor, 0)
            var centerY = value(anchor, 1)
            var width = value(anchor, 2)
            var height = value(anchor, 3)
            if (!centerX.isFinite() ||
                !centerY.isFinite() ||
                !width.isFinite() ||
                !height.isFinite() ||
                width <= 0f ||
                height <= 0f
            ) {
                continue
            }
            val coordinatesAreNormalized = max(
                max(abs(centerX), abs(centerY)),
                max(abs(width), abs(height)),
            ) <= 2f
            if (coordinatesAreNormalized) {
                centerX *= transform.modelWidth
                centerY *= transform.modelHeight
                width *= transform.modelWidth
                height *= transform.modelHeight
            }

            modelBoxToCandidate(
                centerX - width / 2f,
                centerY - height / 2f,
                centerX + width / 2f,
                centerY + height / 2f,
                transform,
                classIndex,
                confidence,
            )?.let(candidates::add)
        }
        return candidates
    }

    private fun decodeEndToEnd(
        output: FloatArray,
        rowCount: Int,
        rowLength: Int,
        transform: LetterboxTransform,
        labels: List<String>,
        confidenceThreshold: Float,
    ): List<Candidate> {
        val candidates = ArrayList<Candidate>()
        for (row in 0 until rowCount) {
            val base = row * rowLength
            val confidence = output.getOrElse(base + 4) { Float.NaN }
            val classIndex = output.getOrElse(base + 5) { Float.NaN }.toInt()
            if (!confidence.isFinite() ||
                confidence < confidenceThreshold ||
                classIndex !in labels.indices ||
                isPerson(classIndex, labels)
            ) {
                continue
            }

            var left = output.getOrElse(base) { Float.NaN }
            var top = output.getOrElse(base + 1) { Float.NaN }
            var right = output.getOrElse(base + 2) { Float.NaN }
            var bottom = output.getOrElse(base + 3) { Float.NaN }
            if (!left.isFinite() ||
                !top.isFinite() ||
                !right.isFinite() ||
                !bottom.isFinite()
            ) {
                continue
            }
            val coordinatesAreNormalized = max(
                max(abs(left), abs(top)),
                max(abs(right), abs(bottom)),
            ) <= 2f
            if (coordinatesAreNormalized) {
                left *= transform.modelWidth
                right *= transform.modelWidth
                top *= transform.modelHeight
                bottom *= transform.modelHeight
            }
            modelBoxToCandidate(
                left,
                top,
                right,
                bottom,
                transform,
                classIndex,
                confidence,
            )?.let(candidates::add)
        }
        return candidates
    }

    private fun modelBoxToCandidate(
        modelLeft: Float,
        modelTop: Float,
        modelRight: Float,
        modelBottom: Float,
        transform: LetterboxTransform,
        classIndex: Int,
        confidence: Float,
    ): Candidate? {
        val left = ((modelLeft - transform.padX) / transform.scale /
            transform.sourceWidth).coerceIn(0f, 1f)
        val top = ((modelTop - transform.padY) / transform.scale /
            transform.sourceHeight).coerceIn(0f, 1f)
        val right = ((modelRight - transform.padX) / transform.scale /
            transform.sourceWidth).coerceIn(0f, 1f)
        val bottom = ((modelBottom - transform.padY) / transform.scale /
            transform.sourceHeight).coerceIn(0f, 1f)
        if (right <= left || bottom <= top) return null
        return Candidate(left, top, right, bottom, classIndex, confidence)
    }

    private fun classAwareNms(
        sorted: List<Candidate>,
        iouThreshold: Float,
        maxResults: Int,
    ): List<Candidate> {
        val kept = ArrayList<Candidate>(min(maxResults, sorted.size))
        for (candidate in sorted) {
            if (kept.any {
                    it.classIndex == candidate.classIndex &&
                        intersectionOverUnion(it, candidate) > iouThreshold
                }
            ) {
                continue
            }
            kept.add(candidate)
            if (kept.size >= maxResults) break
        }
        return kept
    }

    private fun intersectionOverUnion(a: Candidate, b: Candidate): Float {
        val intersectionWidth = max(0f, min(a.right, b.right) - max(a.left, b.left))
        val intersectionHeight = max(0f, min(a.bottom, b.bottom) - max(a.top, b.top))
        val intersection = intersectionWidth * intersectionHeight
        val aArea = (a.right - a.left) * (a.bottom - a.top)
        val bArea = (b.right - b.left) * (b.bottom - b.top)
        val union = aArea + bArea - intersection
        return if (union > 0f) intersection / union else 0f
    }

    private fun isPerson(classIndex: Int, labels: List<String>): Boolean {
        return labels.getOrNull(classIndex)?.trim()?.equals("person", ignoreCase = true) == true
    }
}
