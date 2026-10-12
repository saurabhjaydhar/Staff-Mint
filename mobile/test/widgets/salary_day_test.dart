import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/payroll_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/features/owner/providers/owner_providers.dart';
import 'package:staffmint/features/owner/salary/salary_day_view.dart';

Payslip _slip(String id, String name, int net) => Payslip(
  id: 'ps-$id',
  runId: 'r1',
  employeeId: id,
  employeeName: name,
  month: '2026-09',
  payableDays: 26.5,
  divisor: 30,
  netPaise: net,
  grossPaise: net,
  lines: [
    PayslipLine(code: 'basic', kind: 'earning', label: 'Basic', amountPaise: net),
    if (id == 'e2') const PayslipLine(code: 'advance', kind: 'deduction', label: 'Advance', amountPaise: 250000),
  ],
);

PayrollRun _run(String status, {int revision = 1}) => PayrollRun(
  id: 'r1',
  month: '2026-09',
  status: status,
  revision: revision,
  paidOn: status == 'paid' ? '2026-10-03' : null,
  paymentMethod: status == 'paid' ? 'upi' : null,
  netPaise: 7050000,
  grossPaise: 7300000,
  employees: 3,
  anomalies: const [
    PayrollAnomaly(
      employeeId: 'e2',
      employeeName: 'Amit Verma',
      code: 'big_change',
      message: '₹2,467 less than last month',
    ),
  ],
  payslips: [_slip('e1', 'Pooja Singh', 1336700), _slip('e2', 'Amit Verma', 1153300), _slip('e3', 'Raju', 900000)],
);

class _FakePayrollApi implements PayrollApi {
  final List<String> calls = [];

  @override
  Future<PayrollRun> approve(String id) async {
    calls.add('approve:$id');
    return _run('approved');
  }

  @override
  Future<int> sendPayslips(String runId, {List<String>? payslipIds}) async {
    calls.add('send:$runId');
    return 3;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakePayrollApi api;

  Future<void> pump(WidgetTester tester, {PayrollRun? run}) async {
    api = _FakePayrollApi();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          payrollApiProvider.overrideWithValue(api),
          payrollRunsProvider.overrideWith((ref, month) async => [run ?? _run('draft')]),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SalaryDayView(month: '2026-09')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('salary day shows the cash needed, flagged staff first, then "others look fine"', (tester) async {
    await pump(tester);

    expect(find.text('Total to pay this month'), findsOneWidget);
    expect(find.text('Step 1 · Check attendance'), findsOneWidget);
    expect(find.text('1 to check below'), findsOneWidget);
    expect(find.text('₹70,500'), findsOneWidget);
    expect(find.text('−₹2,500 advance'), findsOneWidget);

    final flag = find.byKey(const Key('flag_e2'));
    final others = find.byKey(const Key('othersFine'));
    expect(flag, findsOneWidget);
    expect(find.text('Amit Verma: ₹2,467 less than last month'), findsOneWidget);
    expect(find.text('2 others look fine'), findsOneWidget);
    expect(tester.getTopLeft(flag).dy, lessThan(tester.getTopLeft(others).dy));

    // Fine staff stay collapsed until asked for.
    expect(find.text('Pooja Singh'), findsNothing);
    await tester.tap(others);
    await tester.pumpAndSettle();
    expect(find.text('Pooja Singh'), findsOneWidget);
    expect(find.text('Raju'), findsOneWidget);

    // "Looks right" moves the flagged person into the fine list.
    await tester.tap(find.byKey(const Key('flagOk_e2')));
    await tester.pumpAndSettle();
    expect(flag, findsNothing);
    expect(find.text('All 3 staff look fine'), findsOneWidget);
    expect(find.text('Slide to approve & send salary slips'), findsOneWidget);
  });

  testWidgets('one slide approves, sends payslips and shows the success screen', (tester) async {
    await pump(tester);
    await tester.drag(find.byKey(const Key('slideThumb')), const Offset(800, 0));
    await tester.pumpAndSettle();

    expect(api.calls, ['approve:r1', 'send:r1']);
    expect(find.text('Salary approved!'), findsOneWidget);
    expect(find.textContaining('Salary slips are going to 3 staff'), findsOneWidget);
  });

  testWidgets('a paid month asks nothing: paid line, a "done" card and one plain "Change salary"', (tester) async {
    await pump(tester, run: _run('paid', revision: 2));

    expect(find.text('Paid on 3 Oct 2026 · UPI'), findsOneWidget);
    expect(find.byKey(const Key('flag_e2')), findsNothing);
    expect(find.text('Is that right?'), findsNothing);
    expect(find.byKey(const Key('salaryDone')), findsOneWidget);
    expect(find.text('September is done'), findsOneWidget);
    expect(find.text('3 salary slips sent. Staff can see them in their app.'), findsOneWidget);
    expect(find.text('Need to change something?'), findsOneWidget);
    expect(find.text('Changed after approval · old slip kept'), findsOneWidget);
    expect(find.text('Change salary'), findsOneWidget);
    expect(find.textContaining('version'), findsNothing);
    expect(find.byKey(const Key('salarySlider')), findsNothing);
  });

  testWidgets('days with no attendance ask "Count them as absent?" with buttons that say what they do', (tester) async {
    final draft = _run('draft');
    await pump(
      tester,
      run: PayrollRun(
        id: draft.id,
        month: draft.month,
        employees: 3,
        anomalies: const [
          PayrollAnomaly(
            employeeId: 'e3',
            employeeName: 'Raju',
            code: 'unmarked_days',
            message: '3 day(s) have no attendance',
          ),
        ],
        payslips: draft.payslips,
      ),
    );
    expect(find.textContaining('Count them as absent?'), findsOneWidget);
    expect(find.text('Yes, absent'), findsOneWidget);
    expect(find.text('Fix days'), findsOneWidget);
  });
}
