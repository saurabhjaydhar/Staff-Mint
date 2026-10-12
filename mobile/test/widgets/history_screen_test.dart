import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/misc_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/owner/more/audit_screen.dart';

class _FakeAuditApi implements AuditApi {
  final categories = <String?>[];

  @override
  Future<List<AuditLog>> list({
    String? entity,
    String? entityId,
    String? category,
    int limit = 50,
    String? before,
  }) async {
    categories.add(category);
    final now = DateTime.now();
    final all = [
      AuditLog(
        id: 'a1',
        actorName: 'Saurabh',
        channel: 'assistant',
        action: 'attendance.override',
        entity: 'attendance',
        at: now,
        text: 'Raju: 1 Oct set to Absent',
        category: 'attendance',
        changes: const [
          AuditChange(label: 'Status', from: 'Present', to: 'Absent'),
          AuditChange(label: 'Reason', to: 'Did not come'),
        ],
      ),
      AuditLog(
        id: 'a2',
        actorName: 'Saurabh',
        channel: 'app',
        action: 'advance.create',
        entity: 'advance',
        at: now.subtract(const Duration(days: 1)),
        text: 'Raju: advance of ₹500 given',
        category: 'salary',
      ),
    ];
    return category == null ? all : all.where((a) => a.category == category).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('history reads like sentences, grouped by day; tap shows what changed; filters by kind', (tester) async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeAuditApi();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs), auditApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: AuditScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('History of changes'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Raju: 1 Oct set to Absent'), findsOneWidget);
    expect(find.textContaining('by Saurabh · via Mint'), findsOneWidget);
    // No raw codes or JSON.
    expect(find.textContaining('attendance.override'), findsNothing);
    expect(find.textContaining('{'), findsNothing);

    await tester.tap(find.text('Raju: 1 Oct set to Absent'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('historyChanges_a1')), findsOneWidget);
    expect(find.textContaining('Did not come'), findsOneWidget);

    await tester.dragUntilVisible(
      find.byKey(const Key('historyFilter_salary')),
      find.byKey(const Key('historyFilter_all')),
      const Offset(-120, 0),
    );
    await tester.tap(find.byKey(const Key('historyFilter_salary')));
    await tester.pumpAndSettle();
    expect(api.categories.last, 'salary');
    expect(find.text('Raju: advance of ₹500 given'), findsOneWidget);
    expect(find.text('Raju: 1 Oct set to Absent'), findsNothing);
  });
}
