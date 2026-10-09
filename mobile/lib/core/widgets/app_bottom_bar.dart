import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import 'bilingual.dart';

class NavItem {
  const NavItem({required this.icon, required this.activeIcon, required this.label, this.key});
  final IconData icon;
  final IconData activeIcon;
  final Bi label;
  final Key? key;
}

/// Light bottom navigation with Hindi labels + English hints and an optional
/// raised centre widget (the Mint mic) that pops above the top border.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key, required this.items, required this.currentIndex, required this.onTap, this.center});
  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Widget? center;

  static const _barHeight = 66.0;
  static const _raise = 24.0;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final slots = <Widget>[for (var i = 0; i < items.length; i++) Expanded(child: _item(i))];
    if (center != null) {
      slots.insert(
        items.length ~/ 2,
        SizedBox(
          width: 76,
          child: Align(alignment: Alignment.topCenter, child: center),
        ),
      );
    }
    final raise = center == null ? 0.0 : _raise;
    return SizedBox(
      height: _barHeight + raise + bottom,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _barHeight + bottom,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.line, width: 1.5)),
              ),
            ),
          ),
          Positioned.fill(
            bottom: bottom,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: slots),
          ),
        ],
      ),
    );
  }

  Widget _item(int i) {
    final item = items[i];
    final selected = i == currentIndex;
    final color = selected ? AppColors.ink : AppColors.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label.text,
      excludeSemantics: true,
      child: InkWell(
        key: item.key,
        onTap: () => onTap(i),
        child: SizedBox(
          height: _barHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? item.activeIcon : item.icon, color: color, size: 24),
              const SizedBox(height: 2),
              BilingualLabel(
                item.label,
                crossAxisAlignment: CrossAxisAlignment.center,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color, height: 1.1),
                hintStyle: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: color, height: 1.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Raised round mint mic: tap to open Mint, hold to talk (release to send).
class MintMicButton extends StatelessWidget {
  const MintMicButton({
    super.key,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
    this.recording = false,
    this.semanticLabel,
  });
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final bool recording;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel ?? 'Mint',
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      key: const Key('mintMic'),
      onTap: onTap,
      onLongPressStart: (_) => onHoldStart(),
      onLongPressEnd: (_) => onHoldEnd(),
      onLongPressCancel: onHoldEnd,
      child: AnimatedScale(
        scale: recording ? 1.12 : 1,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: recording ? AppColors.red : AppColors.mint,
            border: Border.all(color: AppColors.paper, width: 5),
            boxShadow: [
              BoxShadow(
                color: (recording ? AppColors.red : AppColors.mint).withValues(alpha: 0.45),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(recording ? Icons.graphic_eq_rounded : Icons.mic_rounded, color: Colors.white, size: 28),
        ),
      ),
    ),
  );
}
