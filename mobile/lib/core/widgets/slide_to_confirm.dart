import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';

/// UPI-style "slide to pay": money actions need a deliberate swipe.
///
/// Drag the thumb to the end to confirm. For accessibility (and as a
/// fallback for anyone who cannot drag) a long-press on the track, or the
/// screen-reader long-press action, also confirms.
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.enabled = true,
    this.busy = false,
    this.color = AppColors.mint,
  });

  final String label;
  final VoidCallback onConfirmed;
  final bool enabled;
  final bool busy;
  final Color color;

  /// Fraction of the track the thumb must cross to count as confirmed.
  static const threshold = 0.85;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> {
  static const _height = 62.0;
  static const _pad = 5.0;
  static const _thumb = _height - _pad * 2;

  double _dx = 0;
  bool _dragging = false;

  bool get _active => widget.enabled && !widget.busy;

  void _complete() {
    if (!_active) return;
    HapticFeedback.mediumImpact();
    widget.onConfirmed();
    // Slide back so the control is ready again (after the action, if the
    // parent marks itself busy meanwhile).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.busy && !_dragging) setState(() => _dx = 0);
    });
  }

  @override
  void didUpdateWidget(SlideToConfirm old) {
    super.didUpdateWidget(old);
    if (old.busy && !widget.busy) _dx = 0;
  }

  @override
  Widget build(BuildContext context) {
    final color = _active ? widget.color : AppColors.line;
    return Semantics(
      button: true,
      enabled: _active,
      label: widget.label,
      hint: context.s.slideA11yHint,
      onLongPress: _active ? _complete : null,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, c) {
          final maxDx = (c.maxWidth - _thumb - _pad * 2).clamp(0.0, double.infinity);
          final progress = maxDx == 0 ? 0.0 : (_dx / maxDx).clamp(0.0, 1.0);
          return GestureDetector(
            onLongPress: _active ? _complete : null,
            child: Container(
              height: _height,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.only(left: _thumb + 16, right: 16),
                      child: Center(
                        child: Opacity(
                          opacity: 1 - progress * 0.8,
                          child: Text(
                            widget.label,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _active ? Colors.white : AppColors.muted,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    left: _pad + _dx,
                    top: _pad,
                    child: GestureDetector(
                      key: const Key('slideThumb'),
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: _active ? (_) => setState(() => _dragging = true) : null,
                      onHorizontalDragUpdate: _active
                          ? (d) => setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, maxDx))
                          : null,
                      onHorizontalDragEnd: _active
                          ? (_) {
                              final reached = maxDx > 0 && _dx >= maxDx * SlideToConfirm.threshold;
                              setState(() {
                                _dragging = false;
                                _dx = reached ? maxDx : 0;
                              });
                              if (reached) _complete();
                            }
                          : null,
                      child: Container(
                        width: _thumb,
                        height: _thumb,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: widget.busy
                            ? Padding(
                                padding: const EdgeInsets.all(14),
                                child: CircularProgressIndicator(strokeWidth: 3, color: widget.color),
                              )
                            : Icon(
                                Icons.keyboard_double_arrow_right_rounded,
                                color: _active ? widget.color : AppColors.muted,
                                size: 28,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
