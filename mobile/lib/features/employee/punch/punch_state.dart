import '../../../core/models/models.dart';
import '../../../core/utils/dates.dart';
import 'punch_queue.dart';

enum PunchButtonState { checkIn, checkOut, completed }

/// What the big button should offer, combining server punches with punches
/// still waiting in the offline queue (for [today], device-local date).
PunchButtonState deriveButtonState({Attendance? record, List<PendingPunch> pending = const [], required String today}) {
  final events = <(DateTime, String)>[
    for (final p in record?.punches ?? const <Punch>[]) (p.clientTime, p.type),
    for (final p in pending)
      if (Dates.toApiDate(p.clientTime.toLocal()) == today) (p.clientTime, p.type),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (events.isEmpty) return PunchButtonState.checkIn;
  return events.last.$2 == 'in' ? PunchButtonState.checkOut : PunchButtonState.completed;
}

/// The punch type the button will send in [state].
String punchTypeFor(PunchButtonState state) => state == PunchButtonState.checkOut ? 'out' : 'in';
