package com.grozziie.opencv_object_detection;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/** Pure-Java YOLO decoding and class-aware non-maximum suppression. */
final class YoloPostprocessor {
    private YoloPostprocessor() {}

    static List<DetectionModels.Detection> decode(
            float[] output,
            int[] outputDimensions,
            List<String> labels,
            DetectionModels.LetterboxTransform transform,
            float confidenceThreshold,
            float iouThreshold,
            int maxResults
    ) {
        if (output.length == 0 || labels.isEmpty() || maxResults <= 0) {
            return Collections.emptyList();
        }
        int featureCount = labels.size() + 4;
        int[] dimensions = positiveDimensions(outputDimensions);
        int last = dimensions.length == 0 ? 0 : dimensions[dimensions.length - 1];
        int secondLast = dimensions.length < 2 ? 0 : dimensions[dimensions.length - 2];

        List<Candidate> candidates;
        if (secondLast == featureCount && last > 0) {
            candidates = decodeRaw(
                    output,
                    last,
                    featureCount,
                    true,
                    transform,
                    labels,
                    confidenceThreshold
            );
        } else if (last == featureCount && secondLast > 0) {
            candidates = decodeRaw(
                    output,
                    secondLast,
                    featureCount,
                    false,
                    transform,
                    labels,
                    confidenceThreshold
            );
        } else if (output.length % featureCount == 0) {
            candidates = decodeRaw(
                    output,
                    output.length / featureCount,
                    featureCount,
                    true,
                    transform,
                    labels,
                    confidenceThreshold
            );
        } else {
            return Collections.emptyList();
        }

        candidates.sort(Comparator.comparingDouble((Candidate value) -> value.confidence).reversed());
        List<Candidate> kept = classAwareNms(candidates, iouThreshold, maxResults);
        List<DetectionModels.Detection> results = new ArrayList<>(kept.size());
        for (Candidate candidate : kept) {
            results.add(new DetectionModels.Detection(
                    candidate.left,
                    candidate.top,
                    candidate.right,
                    candidate.bottom,
                    labels.get(candidate.classIndex),
                    candidate.classIndex,
                    candidate.confidence
            ));
        }
        return results;
    }

    static boolean hasSupportedLayout(int[] outputDimensions, int classCount) {
        int[] dimensions = positiveDimensions(outputDimensions);
        if (dimensions.length < 2) return false;
        int features = classCount + 4;
        int last = dimensions[dimensions.length - 1];
        int secondLast = dimensions[dimensions.length - 2];
        return last == features || secondLast == features;
    }

    private static List<Candidate> decodeRaw(
            float[] output,
            int anchorCount,
            int featureCount,
            boolean channelsFirst,
            DetectionModels.LetterboxTransform transform,
            List<String> labels,
            float confidenceThreshold
    ) {
        List<Candidate> candidates = new ArrayList<>();
        for (int anchor = 0; anchor < anchorCount; anchor++) {
            int classIndex = -1;
            float confidence = Float.NEGATIVE_INFINITY;
            for (int classOffset = 0; classOffset < labels.size(); classOffset++) {
                float score = value(
                        output,
                        anchor,
                        classOffset + 4,
                        anchorCount,
                        featureCount,
                        channelsFirst
                );
                if (Float.isFinite(score) && score > confidence) {
                    confidence = score;
                    classIndex = classOffset;
                }
            }
            if (classIndex < 0
                    || confidence < confidenceThreshold
                    || labels.get(classIndex).trim().equalsIgnoreCase("person")) {
                continue;
            }

            float centerX = value(output, anchor, 0, anchorCount, featureCount, channelsFirst);
            float centerY = value(output, anchor, 1, anchorCount, featureCount, channelsFirst);
            float width = value(output, anchor, 2, anchorCount, featureCount, channelsFirst);
            float height = value(output, anchor, 3, anchorCount, featureCount, channelsFirst);
            if (!Float.isFinite(centerX)
                    || !Float.isFinite(centerY)
                    || !Float.isFinite(width)
                    || !Float.isFinite(height)
                    || width <= 0f
                    || height <= 0f) {
                continue;
            }
            float maxCoordinate = Math.max(
                    Math.max(Math.abs(centerX), Math.abs(centerY)),
                    Math.max(Math.abs(width), Math.abs(height))
            );
            if (maxCoordinate <= 2f) {
                centerX *= transform.modelWidth;
                centerY *= transform.modelHeight;
                width *= transform.modelWidth;
                height *= transform.modelHeight;
            }
            Candidate candidate = modelBoxToCandidate(
                    centerX - width / 2f,
                    centerY - height / 2f,
                    centerX + width / 2f,
                    centerY + height / 2f,
                    transform,
                    classIndex,
                    confidence
            );
            if (candidate != null) candidates.add(candidate);
        }
        return candidates;
    }

    private static float value(
            float[] output,
            int anchor,
            int feature,
            int anchorCount,
            int featureCount,
            boolean channelsFirst
    ) {
        int index = channelsFirst
                ? feature * anchorCount + anchor
                : anchor * featureCount + feature;
        return index >= 0 && index < output.length ? output[index] : Float.NaN;
    }

    private static Candidate modelBoxToCandidate(
            float modelLeft,
            float modelTop,
            float modelRight,
            float modelBottom,
            DetectionModels.LetterboxTransform transform,
            int classIndex,
            float confidence
    ) {
        float left = clamp01(
                (modelLeft - transform.padX) / transform.scale / transform.sourceWidth
        );
        float top = clamp01(
                (modelTop - transform.padY) / transform.scale / transform.sourceHeight
        );
        float right = clamp01(
                (modelRight - transform.padX) / transform.scale / transform.sourceWidth
        );
        float bottom = clamp01(
                (modelBottom - transform.padY) / transform.scale / transform.sourceHeight
        );
        if (right <= left || bottom <= top) return null;
        return new Candidate(left, top, right, bottom, classIndex, confidence);
    }

    private static List<Candidate> classAwareNms(
            List<Candidate> sorted,
            float iouThreshold,
            int maxResults
    ) {
        List<Candidate> kept = new ArrayList<>(Math.min(sorted.size(), maxResults));
        for (Candidate candidate : sorted) {
            boolean overlaps = false;
            for (Candidate existing : kept) {
                if (existing.classIndex == candidate.classIndex
                        && intersectionOverUnion(existing, candidate) > iouThreshold) {
                    overlaps = true;
                    break;
                }
            }
            if (overlaps) continue;
            kept.add(candidate);
            if (kept.size() >= maxResults) break;
        }
        return kept;
    }

    private static float intersectionOverUnion(Candidate a, Candidate b) {
        float width = Math.max(0f, Math.min(a.right, b.right) - Math.max(a.left, b.left));
        float height = Math.max(0f, Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top));
        float intersection = width * height;
        float aArea = (a.right - a.left) * (a.bottom - a.top);
        float bArea = (b.right - b.left) * (b.bottom - b.top);
        float union = aArea + bArea - intersection;
        return union > 0f ? intersection / union : 0f;
    }

    private static int[] positiveDimensions(int[] dimensions) {
        int count = 0;
        for (int dimension : dimensions) {
            if (dimension > 0) count++;
        }
        int[] result = new int[count];
        int target = 0;
        for (int dimension : dimensions) {
            if (dimension > 0) result[target++] = dimension;
        }
        return result;
    }

    private static float clamp01(float value) {
        return Math.max(0f, Math.min(1f, value));
    }

    private static final class Candidate {
        final float left;
        final float top;
        final float right;
        final float bottom;
        final int classIndex;
        final float confidence;

        Candidate(
                float left,
                float top,
                float right,
                float bottom,
                int classIndex,
                float confidence
        ) {
            this.left = left;
            this.top = top;
            this.right = right;
            this.bottom = bottom;
            this.classIndex = classIndex;
            this.confidence = confidence;
        }
    }
}
