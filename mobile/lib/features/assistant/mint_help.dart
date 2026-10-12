import '../../core/i18n/strings.dart';
import '../../core/router/routes.dart';
import 'assistant_controller.dart';

const _askWords = ['how', 'where', 'kaise', 'kaisa', 'kahan', 'kaha', 'kidhar', 'कैसे', 'कहाँ', 'कहां', 'किधर'];

/// Topic keywords → (answer, screen). Checked in order; first match wins.
List<(List<String>, String Function(S), String)> _topics() => [
  (
    [' ca ', 'accountant', 'partner', 'co-owner', 'manager', 'पार्टनर', 'मैनेजर'],
    (s) => s.helpTeamAnswer,
    Routes.ownerTeam,
  ),
  (['pf', 'esi'], (s) => s.helpStatutory, Routes.ownerStatutory),
  (['late', 'half day', 'grace', 'लेट', 'आधा दिन'], (s) => s.helpLateRules, Routes.ownerAttendanceRules),
  (
    ['holiday', 'festival', 'tyohar', 'shift', 'timing', 'weekly off', 'त्योहार', 'शिफ़्ट', 'शिफ्ट', 'समय'],
    (s) => s.helpTimings,
    Routes.ownerTimings,
  ),
  (['advance', 'udhaar', 'udhar', 'एडवांस', 'उधार'], (s) => s.helpAdvance, Routes.ownerSalary),
  (
    ['add staff', 'staff add', 'new staff', 'naya staff', 'staff jod', 'स्टाफ़ जोड़', 'स्टाफ जोड़'],
    (s) => s.helpAddStaff,
    Routes.ownerStaffAdd,
  ),
  (['report', 'excel', 'pdf', 'रिपोर्ट'], (s) => s.helpReports, Routes.ownerReports),
  (['plan', 'payment', 'subscription', 'प्लान', 'पेमेंट'], (s) => s.helpPlan, Routes.ownerBilling),
];

/// Answers "how do I…/where is…" questions on the phone, with a button to the
/// right screen. Returns null when the text is a command for Mint's server.
ChatMessage? mintHelpFor(S s, String text) {
  final t = ' ${text.toLowerCase().trim()} ';
  if (!_askWords.any(t.contains)) return null;
  for (final (words, answer, route) in _topics()) {
    if (words.any(t.contains)) return ChatMessage.help(answer(s), route: route, routeLabel: s.openScreen);
  }
  return null;
}
