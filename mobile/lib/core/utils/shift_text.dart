import '../i18n/strings.dart';
import '../models/models.dart';
import 'dates.dart';

/// "9:00 AM – 9:00 PM · Sunday off" — a shift in words an owner recognises.
String shiftText(S s, Shift sh, {bool withName = false}) => [
  if (withName) sh.name,
  '${Dates.hhmmToDisplay(sh.start, s.languageCode)} – ${Dates.hhmmToDisplay(sh.end, s.languageCode)}',
  if (sh.weeklyOff.isNotEmpty) s.daysOff(Dates.weekdayNames(sh.weeklyOff, s.languageCode)),
].join(' · ');

/// The shift used for staff without one of their own.
Shift? defaultShiftOf(List<Shift> shifts) => shifts.where((x) => x.isDefault).firstOrNull ?? shifts.firstOrNull;
