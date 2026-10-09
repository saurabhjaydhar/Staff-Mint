import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import 'receipt.dart';

/// Full-screen "✓ done" moment, like a UPI payment success: tick with
/// ripple rings, a receipt and one Done button. Sound + vibration on open.
class SuccessScreen extends StatefulWidget {
  const SuccessScreen({
    super.key,
    required this.title,
    this.subtitle,
    this.rows = const [],
    this.note,
    this.offline = false,
  });

  final String title;
  final String? subtitle;
  final List<(String, String)> rows;
  final String? note;

  /// Saved on the phone, not yet on the server: amber, cloud icon.
  final bool offline;

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

/// Pushes [SuccessScreen] over everything and completes when it is closed.
Future<void> showSuccessScreen(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<(String, String)> rows = const [],
  String? note,
  bool offline = false,
}) => Navigator.of(context, rootNavigator: true).push<void>(
  PageRouteBuilder<void>(
    fullscreenDialog: true,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => SuccessScreen(title: title, subtitle: subtitle, rows: rows, note: note, offline: offline),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ),
);

class _SuccessScreenState extends State<SuccessScreen> {
  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final bg = widget.offline ? AppColors.amberDark : AppColors.mint;
    return Scaffold(
      key: Key(widget.offline ? 'successOffline' : 'successOnline'),
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                children: [
                  Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.6, end: 1),
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutBack,
                      builder: (_, v, child) => Transform.scale(scale: v, child: child),
                      child: _Tick(color: bg, offline: widget.offline),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, height: 1.1),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 16),
                    ),
                  ],
                  if (widget.rows.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                      child: Column(
                        children: [
                          for (var i = 0; i < widget.rows.length; i++)
                            ReceiptRow(label: widget.rows[i].$1, value: widget.rows[i].$2, divider: i > 0),
                        ],
                      ),
                    ),
                  ],
                  if (widget.note != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      widget.note!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  key: const Key('successDone'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(s.doneBi.joined, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.color, required this.offline});
  final Color color;
  final bool offline;

  @override
  Widget build(BuildContext context) => Container(
    width: 184,
    height: 184,
    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.08)),
    alignment: Alignment.center,
    child: Container(
      width: 152,
      height: 152,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.18)),
      alignment: Alignment.center,
      child: Container(
        width: 120,
        height: 120,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
        child: Icon(offline ? Icons.cloud_done_rounded : Icons.check_rounded, size: 72, color: color),
      ),
    ),
  );
}
