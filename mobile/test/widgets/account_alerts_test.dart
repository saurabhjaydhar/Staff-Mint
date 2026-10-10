import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/accounts/accounts_screen.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';

class _FakeAuth extends AuthController {
  static final accepted = <String>[];
  static final stopped = <String>[];

  @override
  SessionState build() => SessionState(
    status: SessionStatus.authenticated,
    user: const User(id: 'u1', phone: '9876543210', name: 'Ravi', role: UserRole.owner, companyId: 'c1'),
    pendingTransfers: const [
      TransferOffer(id: 't1', companyName: 'Gupta Sweets', kind: 'transfer', fromName: 'Mohan Gupta'),
    ],
    recoveryHolds: [RecoveryHold(id: 'h1', businessName: 'Sharma Medical', holdUntil: DateTime(2026, 10, 17))],
  );

  @override
  Future<void> decideTransfer(String transferId, {required bool accept}) async {
    if (accept) accepted.add(transferId);
    state = state.copyWith(pendingTransfers: const []);
  }

  @override
  Future<void> stopRecovery(String id) async {
    stopped.add(id);
    state = state.copyWith(recoveryHolds: const []);
  }
}

void main() {
  testWidgets('ownership offers can be accepted and recoveries stopped right from home', (tester) async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_FakeAuth.new),
        ],
        child: const MaterialApp(home: Scaffold(body: AccountAlerts())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gupta Sweets: become the owner?'), findsOneWidget);
    expect(find.text('Mohan Gupta is handing the business to you.'), findsOneWidget);
    expect(find.text('Sharma Medical: owner account is being recovered'), findsOneWidget);
    expect(find.textContaining('17 Oct'), findsOneWidget);
    await tester.tap(find.byKey(const Key('acceptOffer-t1')));
    await tester.pumpAndSettle();
    expect(_FakeAuth.accepted, ['t1']);
    await tester.tap(find.byKey(const Key('stopHold-h1')));
    await tester.pumpAndSettle();
    expect(_FakeAuth.stopped, ['h1']);
    expect(find.byType(FilledButton), findsNothing);
  });
}
