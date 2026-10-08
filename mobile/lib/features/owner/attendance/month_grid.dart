import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../providers/owner_providers.dart';

/// Staff × days grid with colored status codes.
class MonthGridView extends ConsumerWidget {
  const MonthGridView({super.key, required this.month});
  final String month;

  static const _nameWidth = 120.0;
  static const _cellWidth = 38.0;
  static const _rowHeight = 44.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final grid = ref.watch(monthGridProvider(month));
    return AsyncBody<MonthGrid>(
      value: grid,
      onRetry: () => ref.invalidate(monthGridProvider(month)),
      data: (g) {
        if (g.rows.isEmpty) return EmptyView(message: s.noAttendanceRows);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(monthGridProvider(month).future),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: _nameWidth),
                        for (final d in g.days)
                          SizedBox(
                            width: _cellWidth,
                            child: Text(
                              d.length >= 10 ? d.substring(8) : d,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        SizedBox(
                          width: 120,
                          child: Text(
                            s.totals,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    for (final r in g.rows)
                      SizedBox(
                        height: _rowHeight,
                        child: Row(
                          children: [
                            SizedBox(
                              width: _nameWidth,
                              child: Text(
                                r.employee.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            for (final d in g.days) _Cell(status: r.days[d]),
                            SizedBox(
                              width: 120,
                              child: Text(
                                '${s.statusCode('present')} ${r.totals['present'] ?? 0} · ${s.statusCode('absent')} ${r.totals['absent'] ?? 0}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final st in const [
                      'present',
                      'late',
                      'absent',
                      'half_day',
                      'leave',
                      'holiday',
                      'week_off',
                      'not_marked',
                    ])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Cell(status: st),
                          Text(s.statusLabel(st)),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(status);
    return Container(
      width: MonthGridView._cellWidth - 4,
      height: 32,
      margin: const EdgeInsets.all(2),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
      child: Text(
        context.s.statusCode(status),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color.lerp(color, Colors.black, 0.4)),
      ),
    );
  }
}
