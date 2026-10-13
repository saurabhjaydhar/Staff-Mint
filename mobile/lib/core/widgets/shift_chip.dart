import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';

/// Each shift keeps one colour everywhere (by its place in the day); days off are grey.
({Color fg, Color bg}) shiftColors(List<Shift> shifts, String? shiftId) {
  const palette = [
    (fg: AppColors.mintDark, bg: AppColors.mintLight),
    (fg: AppColors.indigo, bg: AppColors.indigoLight),
    (fg: AppColors.amberDark, bg: AppColors.amberLight),
    (fg: AppColors.orange, bg: AppColors.orangeLight),
  ];
  final i = shifts.indexWhere((s) => s.id == shiftId);
  return i < 0 ? (fg: AppColors.muted, bg: AppColors.mutedLight) : palette[i % palette.length];
}

/// "9 – 5": the short way people say shift hours.
String shortHours(Shift s) {
  String h(String hhmm) {
    final p = hhmm.split(':');
    final hour = int.tryParse(p.first) ?? 0;
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return p.length > 1 && p[1] != '00' ? '$h12:${p[1]}' : '$h12';
  }

  return '${h(s.start)} – ${h(s.end)}';
}

/// "9:00 AM – 5:00 PM" (Hindi: "सुबह 9:00 – शाम 5:00").
String fullHours(Shift s, String locale) =>
    '${Dates.hhmmToDisplay(s.start, locale)} – ${Dates.hhmmToDisplay(s.end, locale)}';

/// A shift (name + short hours) or "Day off", in the shift's colour.
class ShiftChip extends StatelessWidget {
  const ShiftChip({super.key, required this.shifts, this.shiftId, this.off = false, this.showHours = true});
  final List<Shift> shifts;
  final String? shiftId;
  final bool off;
  final bool showHours;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    Shift? shift;
    for (final x in shifts) {
      if (x.id == shiftId) shift = x;
    }
    final c = off ? (fg: AppColors.muted, bg: AppColors.mutedLight) : shiftColors(shifts, shiftId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            off || shift == null ? s.dayOff : shift.name,
            style: TextStyle(color: c.fg, fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          if (!off && shift != null && showHours) ...[
            const SizedBox(width: 6),
            Text(
              shortHours(shift),
              style: TextStyle(color: c.fg, fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}
