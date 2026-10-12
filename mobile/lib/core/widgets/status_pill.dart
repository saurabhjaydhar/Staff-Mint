import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';

/// Attendance status as icon + word on a tinted pill. Tappable pills show a ▾
/// so they obviously open something, and keep a 48 dp touch target.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.onTap, this.large = false, this.label});
  final String? status;

  /// Overrides the usual word for [status] (e.g. "Not marked" for staff the owner marks).
  final String? label;
  final VoidCallback? onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final st = StatusStyle.of(status);
    final label = this.label ?? context.s.statusShort(status);
    final pill = Container(
      constraints: BoxConstraints(minWidth: large ? 96 : 74),
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 6 : 3),
      decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(9)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(st.icon, size: large ? 17 : 14, color: st.fg),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: st.fg, fontWeight: FontWeight.w800, fontSize: large ? 15 : 13),
            ),
          ),
          if (onTap != null) Icon(Icons.arrow_drop_down_rounded, size: large ? 20 : 17, color: st.fg),
        ],
      ),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      label: '${context.s.changeStatus}: ${context.s.statusLabel(status)}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(alignment: Alignment.centerRight, widthFactor: 1, child: pill),
        ),
      ),
    );
  }
}
