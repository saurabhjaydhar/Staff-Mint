import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/i18n/strings.dart';
import 'package:staffmint/core/models/models.dart';

void main() {
  test('alternating weekly offs read the way people say them', () {
    final sh = Shift.fromJson({
      'id': 's',
      'name': 'Shop',
      'start': '09:00',
      'end': '18:00',
      'weeklyOff': [0, 6],
      'weeklyOffWeeks': {
        '6': [1, 3],
        '2': <int>[],
      },
    });
    expect(sh.weeklyOffWeeks, {
      6: [1, 3],
    });
    expect(const S('en').offDaysText(sh.weeklyOff, sh.weeklyOffWeeks), 'Sunday, 1st & 3rd Saturday');
    expect(const S('hi').offDaysText(sh.weeklyOff, sh.weeklyOffWeeks), 'रविवार, पहला और तीसरा शनिवार');
    expect(const S('en').weeksOfMonth([2, 4]), '2nd & 4th');
  });
}
