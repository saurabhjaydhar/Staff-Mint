import 'package:flutter/material.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../punch/punch_state.dart';

/// The one big round Check-in / Check-out button.
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
    final (label, icon, color) = switch (state) {
      PunchButtonState.checkIn => (s.checkIn, Icons.login_rounded, AppColors.mint),
      PunchButtonState.checkOut => (s.checkOut, Icons.logout_rounded, AppColors.halfDay),
      PunchButtonState.completed => (s.checkInAgain, Icons.replay_rounded, AppColors.mintDark),
    };
    final enabled = !busy && onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: busy ? (busyLabel ?? s.submitting) : label,
      child: SizedBox(
        width: size,
        height: size,
        child: ElevatedButton(
          key: const Key('checkInButton'),
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            backgroundColor: state == PunchButtonState.completed ? Colors.white : color,
            foregroundColor: state == PunchButtonState.completed ? color : Colors.white,
            disabledBackgroundColor: color.withValues(alpha: 0.5),
            disabledForegroundColor: Colors.white,
            elevation: 6,
            side: state == PunchButtonState.completed ? BorderSide(color: color, width: 3) : null,
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
                    Text(busyLabel ?? s.submitting, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 64),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
