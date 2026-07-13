import 'package:flutter/material.dart';

import '../../domain/models/moving_down_capture_contract.dart';

/// Scrollable confirmation dialog for the literal JSONL that will be saved.
class MovingDownJsonlReviewDialog extends StatefulWidget {
  const MovingDownJsonlReviewDialog({super.key, required this.review});

  final MovingDownJsonlReview review;

  @override
  State<MovingDownJsonlReviewDialog> createState() =>
      _MovingDownJsonlReviewDialogState();
}

class _MovingDownJsonlReviewDialogState
    extends State<MovingDownJsonlReviewDialog> {
  final _verticalController = ScrollController();
  final _horizontalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final screenSize = MediaQuery.sizeOf(context);
    return Dialog(
      key: const Key('movingDownJsonlReviewDialog'),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: screenSize.height * 0.86,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Review Moving-Down JSONL',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  Text(
                    'Valid hand frames: ${review.validHandFrames}',
                    key: const Key('validHandFrameCount'),
                  ),
                  Text(
                    'Excluded frames: ${review.excludedFrames}',
                    key: const Key('excludedFrameCount'),
                  ),
                  Text(
                    'Unsafe frames: ${review.unsafeFrames}',
                    key: const Key('unsafeFrameCount'),
                    style: TextStyle(
                      color:
                          review.unsafeFrames == 0
                              ? const Color(0xFF039855)
                              : const Color(0xFFD92D20),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Detected hand: ${_detectedHandLabel(review)}',
                    key: const Key('detectedHandedness'),
                  ),
                  Text(
                    'Landmark FPS: ${review.landmarkFps.toStringAsFixed(2)}',
                    key: const Key('landmarkFps'),
                  ),
                  Text(
                    'Downward: '
                    '${(review.downwardTravel * 100).toStringAsFixed(1)}%',
                  ),
                ],
              ),
              if (review.failureReason != null) ...[
                const SizedBox(height: 8),
                Text(
                  review.failureReason!,
                  key: const Key('reviewFailureReason'),
                  style: const TextStyle(
                    color: Color(0xFFD92D20),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Selected camera frames',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SizedBox(
                key: const Key('selectedFrameImageGallery'),
                height: 142,
                child:
                    review.records.isEmpty
                        ? const Center(
                          child: Text('No valid hand images selected.'),
                        )
                        : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: review.records.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final image =
                                index < review.frameImages.length
                                    ? review.frameImages[index]
                                    : null;
                            final mirrored =
                                review.records[index]['camera_flipped'] == true;
                            final unsafe = review.unsafeFrameIndexes.contains(
                              index,
                            );
                            return DecoratedBox(
                              key:
                                  unsafe ? Key('unsafeFrameImage$index') : null,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color:
                                      unsafe
                                          ? const Color(0xFFD92D20)
                                          : Colors.transparent,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: SizedBox(
                                  width: 108,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: ColoredBox(
                                            color: const Color(0xFF101828),
                                            child:
                                                image == null
                                                    ? const Center(
                                                      child: Icon(
                                                        Icons
                                                            .image_not_supported_outlined,
                                                        color: Color(
                                                          0xFF98A2B3,
                                                        ),
                                                      ),
                                                    )
                                                    : Transform.flip(
                                                      flipX: mirrored,
                                                      child: Image.memory(
                                                        image,
                                                        key: Key(
                                                          'selectedFrameImage$index',
                                                        ),
                                                        fit: BoxFit.cover,
                                                        gaplessPlayback: true,
                                                        errorBuilder:
                                                            (
                                                              _,
                                                              _,
                                                              _,
                                                            ) => const Center(
                                                              child: Icon(
                                                                Icons
                                                                    .broken_image_outlined,
                                                                color: Color(
                                                                  0xFF98A2B3,
                                                                ),
                                                              ),
                                                            ),
                                                      ),
                                                    ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        unsafe
                                            ? 'Frame $index · UNSAFE'
                                            : 'Frame $index',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color:
                                              unsafe
                                                  ? const Color(0xFFD92D20)
                                                  : null,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF101828),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Scrollbar(
                    controller: _verticalController,
                    child: SingleChildScrollView(
                      controller: _verticalController,
                      padding: const EdgeInsets.all(12),
                      child: Scrollbar(
                        controller: _horizontalController,
                        notificationPredicate:
                            (notification) =>
                                notification.metrics.axis == Axis.horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontalController,
                          scrollDirection: Axis.horizontal,
                          child: SelectableText(
                            review.contents,
                            key: const Key('jsonlPreviewText'),
                            style: const TextStyle(
                              color: Color(0xFFD0D5DD),
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('cancelJsonlReviewButton'),
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(review.canGenerate ? 'Cancel' : 'Retake'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('generateJsonlButton'),
                    onPressed:
                        review.canGenerate
                            ? () => Navigator.pop(context, true)
                            : null,
                    child: const Text('Generate JSONL'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _detectedHandLabel(MovingDownJsonlReview review) {
    if (!review.handednessConsistent) return 'Mixed';
    return switch (review.detectedIsRight) {
      true => 'Right',
      false => 'Left',
      null => 'None',
    };
  }
}
