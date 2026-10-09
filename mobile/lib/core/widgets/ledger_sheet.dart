import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The bahi-khata day sheet: a ruled white card with the red margin line.
class LedgerSheet extends StatelessWidget {
  const LedgerSheet({super.key, required this.header, required this.rows, this.margin = _defaultMargin});
  final Widget header;
  final List<Widget> rows;
  final EdgeInsets margin;

  static const marginX = 44.0;
  static const _defaultMargin = EdgeInsets.fromLTRB(14, 12, 14, 0);

  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line, width: 1.5),
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        const Positioned(
          left: marginX,
          top: 0,
          bottom: 0,
          child: SizedBox(width: 1.5, child: ColoredBox(color: AppColors.margin)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            for (var i = 0; i < rows.length; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.lineSoft)),
                ),
                child: rows[i],
              ),
          ],
        ),
      ],
    ),
  );
}

/// Header: muted label, big number "3 / 6" and summary chips, on ruled paper.
class LedgerHeader extends StatelessWidget {
  const LedgerHeader({super.key, required this.label, required this.value, this.total, this.chips = const []});
  final String label;
  final String value;
  final String? total;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _RuledPainter(),
    child: Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line, width: 1.5)),
      ),
      padding: const EdgeInsets.fromLTRB(LedgerSheet.marginX + 12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
              Text.rich(
                TextSpan(
                  text: value,
                  children: [
                    if (total != null)
                      TextSpan(
                        text: ' / $total',
                        style: const TextStyle(fontSize: 20, color: AppColors.muted, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
                key: const Key('ledgerBigNumber'),
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: chips),
          ),
        ],
      ),
    ),
  );
}

/// Small tinted count chip used in ledger headers ("लेट 1").
class LedgerChip extends StatelessWidget {
  const LedgerChip({super.key, required this.label, required this.status});
  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    final st = StatusStyle.of(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(st.icon, size: 12, color: st.fg),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: st.fg),
          ),
        ],
      ),
    );
  }
}

/// One ledger line: time in the margin | name | meta | trailing (status pill).
class LedgerRow extends StatelessWidget {
  const LedgerRow({super.key, required this.margin, required this.title, this.meta, this.trailing, this.onTap});
  final String margin;
  final String title;
  final String? meta;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50),
      child: Row(
        children: [
          SizedBox(
            width: LedgerSheet.marginX,
            child: Text(
              margin,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
            ),
          ),
          if (meta != null)
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 6),
              child: Text(meta!, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
            ),
          if (trailing != null) Padding(padding: const EdgeInsets.only(right: 10), child: trailing),
        ],
      ),
    ),
  );
}

class _RuledPainter extends CustomPainter {
  const _RuledPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = AppColors.ruled;
    for (var y = 31.0; y < size.height; y += 32) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
