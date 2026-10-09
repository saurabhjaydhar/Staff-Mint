import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// White receipt with a zig-zag torn bottom edge (payslips, success screens).
class ReceiptCard extends StatelessWidget {
  const ReceiptCard({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 18)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: padding,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: child,
      ),
      const SizedBox(height: 12, child: CustomPaint(painter: _ZigZagPainter())),
    ],
  );
}

class _ZigZagPainter extends CustomPainter {
  const _ZigZagPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tooth = 16.0;
    final path = Path()..moveTo(0, 0);
    var x = 0.0;
    while (x < size.width) {
      path.lineTo(math.min(x + tooth / 2, size.width), size.height * 0.75);
      path.lineTo(math.min(x + tooth, size.width), 0);
      x += tooth;
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Rotated outlined rubber stamp: "PAID ✓" / "मंज़ूर ✓".
class Stamp extends StatelessWidget {
  const Stamp({super.key, required this.text, this.color = AppColors.mint});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -12 * math.pi / 180,
    child: Opacity(
      opacity: 0.85,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: 1),
            ),
            const SizedBox(width: 4),
            Icon(Icons.check_rounded, color: color, size: 22),
          ],
        ),
      ),
    ),
  );
}

/// "Label ........ value" line with a dashed separator above it.
class ReceiptRow extends StatelessWidget {
  const ReceiptRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.divider = true,
    this.bold = true,
  });
  final String label;
  final String value;
  final Color? valueColor;
  final bool divider;
  final bool bold;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (divider) const DashedDivider(),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Text(label, style: const TextStyle(fontSize: 14.5, color: AppColors.muted)),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: valueColor ?? AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key, this.color = AppColors.line});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 1,
    width: double.infinity,
    child: CustomPaint(painter: _DashPainter(color)),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 4, 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) => oldDelegate.color != color;
}
