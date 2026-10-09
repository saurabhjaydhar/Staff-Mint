import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../providers/owner_providers.dart';

/// Staff × days ledger for a month: tinted cells with a status code, so the
/// colour is never the only signal.
class MonthGridView extends ConsumerWidget {
  const MonthGridView({super.key, required this.month});
  final String month;

  static const _nameWidth = 116.0;
  static const _cellWidth = 34.0;
  static const _rowHeight = 42.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final grid = ref.watch(monthGridProvider(month));
    return AsyncBody<MonthGrid>(
      value: grid,
      onRetry: () => ref.invalidate(monthGridProvider(month)),
      data: (g) {
        if (g.rows.isEmpty) return EmptyView(message: s.noAttendanceRows, icon: Icons.event_busy_outlined);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(monthGridProvider(month).future),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _line(
                        header: true,
                        name: '',
                        cells: [
                          for (final d in g.days)
                            Text(
                              d.length >= 10 ? '${int.tryParse(d.substring(8)) ?? d}' : d,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted,
                                fontSize: 12.5,
                              ),
                            ),
                        ],
                        totals: s.totals,
                      ),
                      for (final r in g.rows)
                        _line(
                          name: r.employee.name,
                          cells: [for (final d in g.days) _Cell(status: r.days[d])],
                          totals:
                              '${s.statusCode('present')} ${r.totals['present'] ?? 0} · ${s.statusCode('absent')} ${r.totals['absent'] ?? 0}',
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
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
                          const SizedBox(width: 2),
                          Text(s.statusLabel(st), style: const TextStyle(fontSize: 13.5)),
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

  Widget _line({required String name, required List<Widget> cells, required String totals, bool header = false}) =>
      Container(
        height: header ? 34 : _rowHeight,
        decoration: BoxDecoration(
          color: header ? AppColors.ruled : null,
          border: const Border(bottom: BorderSide(color: AppColors.lineSoft)),
        ),
        child: Row(
          children: [
            Container(
              width: _nameWidth,
              padding: const EdgeInsets.only(left: 12, right: 6),
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.margin, width: 1.5)),
              ),
              alignment: Alignment.centerLeft,
              height: double.infinity,
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final c in cells)
              SizedBox(
                width: _cellWidth,
                child: Center(child: c),
              ),
            SizedBox(
              width: 112,
              child: Text(
                totals,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: header ? FontWeight.w700 : FontWeight.w500, fontSize: 13),
              ),
            ),
          ],
        ),
      );
}

class _Cell extends StatelessWidget {
  const _Cell({required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final st = StatusStyle.of(status);
    return Container(
      width: MonthGridView._cellWidth - 6,
      height: 28,
      margin: const EdgeInsets.all(2),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(7)),
      child: Text(
        context.s.statusCode(status),
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: st.fg),
      ),
    );
  }
}
