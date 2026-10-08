import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/utils/dates.dart';
import 'package:staffmint/features/employee/punch/punch_queue.dart';
import 'package:staffmint/features/employee/punch/punch_state.dart';

Punch _punch(String type, DateTime t) => Punch(id: '$type$t', type: type, clientTime: t);

PendingPunch _pending(String type, DateTime t) => PendingPunch(
  clientPunchId: 'q$type$t',
  type: type,
  payload: {'clientTime': t.toUtc().toIso8601String()},
  queuedAt: t,
);

void main() {
  final now = DateTime.now();
  final today = Dates.toApiDate(now);
  final morning = DateTime(now.year, now.month, now.day, 9, 5);
  final evening = DateTime(now.year, now.month, now.day, 19, 2);

  Attendance record(List<Punch> punches) => Attendance(id: 'a', employeeId: 'e', date: today, punches: punches);

  test('no punches → Check in', () {
    expect(deriveButtonState(today: today), PunchButtonState.checkIn);
    expect(deriveButtonState(record: record([]), today: today), PunchButtonState.checkIn);
  });

  test('last punch in → Check out', () {
    expect(deriveButtonState(record: record([_punch('in', morning)]), today: today), PunchButtonState.checkOut);
  });

  test('in then out → completed', () {
    expect(
      deriveButtonState(record: record([_punch('in', morning), _punch('out', evening)]), today: today),
      PunchButtonState.completed,
    );
  });

  test('offline queued punches count for today', () {
    expect(deriveButtonState(pending: [_pending('in', morning)], today: today), PunchButtonState.checkOut);
    expect(
      deriveButtonState(record: record([_punch('in', morning)]), pending: [_pending('out', evening)], today: today),
      PunchButtonState.completed,
    );
  });

  test('queued punches from another day are ignored', () {
    final yesterday = morning.subtract(const Duration(days: 1));
    expect(deriveButtonState(pending: [_pending('in', yesterday)], today: today), PunchButtonState.checkIn);
  });

  test('punch type for each state', () {
    expect(punchTypeFor(PunchButtonState.checkIn), 'in');
    expect(punchTypeFor(PunchButtonState.checkOut), 'out');
    expect(punchTypeFor(PunchButtonState.completed), 'in');
  });
}
