import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/i18n/strings.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/router/routes.dart';
import 'package:staffmint/features/assistant/mint_help.dart';
import 'package:staffmint/features/owner/today/leave_cards.dart';

Leave _leave({num? left, num? after, String type = 'paid'}) => Leave(
  id: 'l1',
  employeeId: 'e1',
  employeeName: 'Amit',
  type: type,
  from: '2026-10-14',
  to: '2026-10-15',
  days: 2,
  balanceLeft: left,
  balanceAfter: after,
);

void main() {
  Future<List<String>> pumpLeave(WidgetTester tester, Leave leave) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LeaveDecisionCard(
            leave: leave,
            busy: false,
            onDecide: (a) => calls.add(a ? 'approve' : 'reject'),
            onApproveUnpaid: () => calls.add('unpaid'),
          ),
        ),
      ),
    );
    return calls;
  }

  testWidgets('no paid leaves left: the main button says "Approve as unpaid" and explains the cut', (tester) async {
    final calls = await pumpLeave(tester, _leave(left: 0, after: -2));
    expect(find.textContaining('No paid leaves left'), findsOneWidget);
    expect(find.textContaining('salary is cut for 2 days'), findsOneWidget);
    expect(find.textContaining('-2'), findsNothing);
    expect(find.textContaining('paid leave leaves'), findsNothing);
    expect(find.text('Approve as unpaid'), findsOneWidget);
    expect(find.text('Give as paid leave anyway'), findsOneWidget);

    await tester.tap(find.byKey(const Key('leaveUnpaid_l1')));
    await tester.tap(find.byKey(const Key('leavePaidAnyway_l1')));
    await tester.tap(find.byKey(const Key('leaveNo_l1')));
    expect(calls, ['unpaid', 'approve', 'reject']);
  });

  testWidgets('enough leaves: plain Approve with what is left after', (tester) async {
    await pumpLeave(tester, _leave(left: 5, after: 3));
    expect(find.text('Has 5 paid leaves. After this: 3 left.'), findsOneWidget);
    expect(find.text('Approve as unpaid'), findsNothing);
    expect(find.byKey(const Key('leaveShort_l1')), findsNothing);
  });

  test('Mint answers "how do I…" questions on the phone with the right screen', () {
    const s = S('en');
    final ca = mintHelpFor(s, 'Mera CA kaise add karein?');
    expect(ca?.route, Routes.ownerTeam);
    expect(ca?.text, contains('Team & access'));
    expect(ca?.isHelp, isTrue);
    expect(mintHelpFor(s, 'Holiday kaise lagaye?')?.route, Routes.ownerTimings);
    expect(mintHelpFor(s, 'where do I set PF?')?.route, Routes.ownerStatutory);
    expect(mintHelpFor(s, 'How to download report')?.route, Routes.ownerReports);
    // Commands still go to Mint.
    expect(mintHelpFor(s, 'Raju aaj absent hai'), isNull);
    expect(mintHelpFor(s, 'Pooja ko ₹500 advance do'), isNull);
    // Words that only contain "ca" don't count as CA.
    expect(mintHelpFor(s, 'how to see calendar'), isNull);
  });
}
