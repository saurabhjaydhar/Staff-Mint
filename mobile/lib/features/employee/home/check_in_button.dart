import 'package:flutter/material.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../punch/punch_state.dart';

/// The one big round "हाज़िरी लगाएँ" button with soft rings around it.
/// Mint for check-in, orange for check-out, outlined once the day is done.
class CheckInButton extends StatelessWidget {
  const CheckInButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.busy = false,
    this.busyLabel,
    this.size = 220,
  });

  final PunchButtonState state;
  final VoidCallback? onPressed;
  final bool busy;
  final String? busyLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final (label, hint, icon, color) = switch (state) {
      PunchButtonState.checkIn => (s.checkIn, s.checkInHint, Icons.touch_app_rounded, AppColors.mint),
      PunchButtonState.checkOut => (s.checkOut, s.checkOutHint, Icons.logout_rounded, AppColors.orange),
      PunchButtonState.completed => (s.checkInAgain, null, Icons.replay_rounded, AppColors.mintDark),
    };
    final done = state == PunchButtonState.completed;
    final enabled = !busy && onPressed != null;
    final ring = done ? AppColors.mintLight : color.withValues(alpha: 0.12);
    return Semantics(
      button: true,
      enabled: enabled,
      label: busy ? (busyLabel ?? s.submitting) : label,
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: ring, spreadRadius: 12),
            BoxShadow(color: ring.withValues(alpha: ring.a * 0.5), spreadRadius: 24),
          ],
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: ElevatedButton(
            key: const Key('checkInButton'),
            onPressed: enabled ? onPressed : null,
            style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: done ? Colors.white : color,
              foregroundColor: done ? color : Colors.white,
              disabledBackgroundColor: color.withValues(alpha: 0.6),
              disabledForegroundColor: Colors.white,
              elevation: 0,
              side: done ? BorderSide(color: color, width: 3) : null,
            ),
            child: busy
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 4),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        busyLabel ?? s.submitting,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 52),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, height: 1.1),
                      ),
                      if (hint != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(hint, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
