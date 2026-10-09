import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';

/// Thin segmented progress bar with labels: "✓ जाँचें  • भेजें  भुगतान" (icons, not glyphs).
/// Steps before [current] are done; [current] is in progress.
class StepBar extends StatelessWidget {
  const StepBar({super.key, required this.steps, required this.current});
  final List<Bi> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: steps.map((b) => b.text).join(', '),
      value: '${(current + 1).clamp(1, steps.length)} / ${steps.length}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: i <= current ? AppColors.mint : AppColors.line,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < steps.length; i++)
                Expanded(
                  child: Row(
                    mainAxisAlignment: i == 0
                        ? MainAxisAlignment.start
                        : i == steps.length - 1
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.center,
                    children: [
                      if (i < current) const Icon(Icons.check_rounded, size: 14, color: AppColors.mint),
                      if (i == current) const Icon(Icons.circle, size: 8, color: AppColors.mint),
                      if (i <= current) const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          steps[i].text,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: i == current ? FontWeight.w800 : FontWeight.w600,
                            color: i <= current ? AppColors.ink : AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
