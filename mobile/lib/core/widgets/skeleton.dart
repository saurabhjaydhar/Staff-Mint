import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';

/// A static placeholder block. No shimmer: budget phones and calm screens.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: AppColors.mutedLight, borderRadius: BorderRadius.circular(radius)),
  );
}

/// Card-shaped skeleton rows for lists while data loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4, this.padding = const EdgeInsets.symmetric(vertical: 8)});
  final int count;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.s.loading,
    child: Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppTheme.radius,
                border: Border.all(color: AppColors.line, width: 1.5),
              ),
              child: Row(
                children: [
                  const SkeletonBox(width: 40, height: 40, radius: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: i.isEven ? 150 : 110, height: 14),
                        const SizedBox(height: 8),
                        const SkeletonBox(width: 80, height: 11),
                      ],
                    ),
                  ),
                  const SkeletonBox(width: 64, height: 24, radius: 9),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
