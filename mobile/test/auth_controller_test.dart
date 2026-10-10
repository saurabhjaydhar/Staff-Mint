import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/api/api_exception.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/services/accounts_api.dart';
import 'package:staffmint/core/api/services/auth_api.dart';
import 'package:staffmint/core/api/services/me_api.dart';
import 'package:staffmint/core/storage/key_value_store.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/core/storage/token_storage.dart';
import 'package:staffmint/core/utils/json.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';
import 'package:staffmint/features/employee/punch/punch_providers.dart';
import 'package:staffmint/features/employee/punch/punch_queue.dart';

Json _membership(String id, String company, String role) => {
  'id': id,
  'companyId': 'c-$id',
  'companyName': company,
  'businessType': 'shop',
  'role': role,
};

class _FakeAuthApi implements AuthApi {
  final switched = <({String membershipId, String deviceId, String? refreshToken})>[];
  Map<String, dynamic>? verifyResponse;

  @override
  Future<AuthResult> verifyOtp({
    required String phone,
    required String code,
    required String deviceId,
    String? deviceName,
  }) async => AuthResult.fromJson(verifyResponse!);

  @override
  Future<AuthResult> switchAccount({
    required String membershipId,
    required String deviceId,
    String? refreshToken,
  }) async {
    switched.add((membershipId: membershipId, deviceId: deviceId, refreshToken: refreshToken));
    return AuthResult.fromJson({
      'accessToken': 'a2',
      'refreshToken': 'r2',
      'user': {'id': 'u1', 'phone': '9876543210', 'name': 'Sita', 'role': 'owner', 'companyId': 'c-m2'},
      'needsCompanySetup': false,
      'activeMembershipId': membershipId,
      'memberships': [_membership('m1', 'Sharma Medical', 'employee'), _membership('m2', 'Sita Boutique', 'owner')],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccountsApi implements AccountsApi {
  final answers = <bool>[];

  @override
  Future<AuthResult> answerIdentity(String token, {required bool isMe}) async {
    answers.add(isMe);
    return AuthResult.fromJson({
      'accessToken': 'a3',
      'refreshToken': 'r3',
      'user': {'id': 'u9', 'phone': '9876543210', 'name': '', 'role': 'owner', 'companyId': null},
      'needsCompanySetup': true,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Sync never gets through (offline).
class _OfflineSync extends PunchSyncController {
  @override
  SyncStatus build() => const SyncStatus();

  @override
  Future<SyncReport> syncNow() async => SyncReport.empty;
}

class _FakeMeApi implements MeApi {
  ApiException? error;
  Json response = {
    'user': {
      'id': 'u1',
      'phone': '9876543210',
      'name': 'Sita',
      'role': 'employee',
      'companyId': 'c1',
      'employeeId': 'e1',
    },
    'company': {'id': 'c1', 'name': 'Shop'},
    'employee': {
      'id': 'e1',
      'name': 'Sita',
      'phone': '9876543210',
      'consent': {'location': false},
    },
  };

  @override
  Future<(MeResponse, Json)> me() async {
    if (error != null) throw error!;
    return (MeResponse.fromJson(response), response);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MemoryKeyValueStore store;
  late _FakeMeApi meApi;
  late _FakeAuthApi authApi;
  late _FakeAccountsApi accountsApi;
  late PunchQueue queue;
  late SharedPreferences prefs;

  ProviderContainer make() => ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      secureStoreProvider.overrideWithValue(store),
      meApiProvider.overrideWithValue(meApi),
      authApiProvider.overrideWithValue(authApi),
      accountsApiProvider.overrideWithValue(accountsApi),
      sharedPreferencesProvider.overrideWithValue(prefs),
      punchQueueProvider.overrideWithValue(queue),
      punchSyncProvider.overrideWith(_OfflineSync.new),
    ],
  );

  Future<SessionState> settle(ProviderContainer c) async {
    c.read(authControllerProvider);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      if (c.read(authControllerProvider).status != SessionStatus.unknown) break;
    }
    return c.read(authControllerProvider);
  }

  setUp(() async {
    store = MemoryKeyValueStore();
    meApi = _FakeMeApi();
    authApi = _FakeAuthApi();
    accountsApi = _FakeAccountsApi();
    queue = PunchQueue(MemoryPunchQueueStore());
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('no tokens → unauthenticated', () async {
    final c = make();
    addTearDown(c.dispose);
    expect((await settle(c)).status, SessionStatus.unauthenticated);
  });

  test('restores from /me and caches it; employee without consent needs consent', () async {
    await TokenStorage(store).saveTokens(accessToken: 'a', refreshToken: 'r');
    final c = make();
    addTearDown(c.dispose);
    final s = await settle(c);
    expect(s.isAuthenticated, isTrue);
    expect(s.isEmployee, isTrue);
    expect(s.needsConsent, isTrue);
    expect(await TokenStorage(store).readSessionCache(), isNotNull);
  });

  test('offline start uses the cached session (employee can still punch)', () async {
    final tokens = TokenStorage(store);
    await tokens.saveTokens(accessToken: 'a', refreshToken: 'r');
    await tokens.writeSessionCache(meApi.response);
    meApi.error = ApiException.network();
    final c = make();
    addTearDown(c.dispose);
    final s = await settle(c);
    expect(s.isAuthenticated, isTrue);
    expect(s.user!.name, 'Sita');
  });

  test('offline start without cache offers a retry instead of logging out', () async {
    await TokenStorage(store).saveTokens(accessToken: 'a', refreshToken: 'r');
    meApi.error = ApiException.network();
    final c = make();
    addTearDown(c.dispose);
    c.read(authControllerProvider);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final s = c.read(authControllerProvider);
    expect(s.status, SessionStatus.unknown);
    expect(s.restoreFailed, isTrue);
    expect(await TokenStorage(store).readAccessToken(), 'a');
  });

  test('owner without company needs setup', () async {
    await TokenStorage(store).saveTokens(accessToken: 'a', refreshToken: 'r');
    meApi.response = {
      'user': {'id': 'u2', 'phone': '9876543211', 'name': '', 'role': 'owner', 'companyId': null},
      'company': null,
      'employee': null,
    };
    final c = make();
    addTearDown(c.dispose);
    final s = await settle(c);
    expect(s.needsCompanySetup, isTrue);
  });

  group('accounts', () {
    Future<ProviderContainer> twoAccounts() async {
      await TokenStorage(store).saveTokens(accessToken: 'a', refreshToken: 'r');
      meApi.response = {
        ...meApi.response,
        'activeMembershipId': 'm1',
        'memberships': [_membership('m1', 'Sharma Medical', 'employee'), _membership('m2', 'Sita Boutique', 'owner')],
      };
      final c = make();
      addTearDown(c.dispose);
      await settle(c);
      return c;
    }

    test('a restored session knows its accounts but does not ask again', () async {
      final c = await twoAccounts();
      final s = c.read(authControllerProvider);
      expect(s.memberships.map((m) => m.companyName), ['Sharma Medical', 'Sita Boutique']);
      expect(s.activeMembership?.role, 'employee');
      expect(s.hasManyAccounts, isTrue);
      expect(s.needsAccountChoice, isFalse);
    });

    test('switching sends the device and old token, saves new tokens and reloads the session', () async {
      final c = await twoAccounts();
      meApi.response = {
        'user': {'id': 'u1', 'phone': '9876543210', 'name': 'Sita', 'role': 'owner', 'companyId': 'c-m2'},
        'company': {'id': 'c-m2', 'name': 'Sita Boutique'},
        'employee': null,
        'activeMembershipId': 'm2',
        'memberships': [_membership('m1', 'Sharma Medical', 'employee'), _membership('m2', 'Sita Boutique', 'owner')],
      };
      await c.read(authControllerProvider.notifier).switchTo('m2');
      expect(authApi.switched.single.membershipId, 'm2');
      expect(authApi.switched.single.refreshToken, 'r');
      expect(authApi.switched.single.deviceId, isNotEmpty);
      expect(await TokenStorage(store).readAccessToken(), 'a2');
      expect(await TokenStorage(store).readRefreshToken(), 'r2');
      final s = c.read(authControllerProvider);
      expect(s.isOwner, isTrue);
      expect(s.company?.name, 'Sita Boutique');
      expect(s.activeMembershipId, 'm2');
    });

    test('choosing the account already open only closes the chooser', () async {
      final c = await twoAccounts();
      c.read(authControllerProvider.notifier).state = c.read(authControllerProvider).copyWith(needsAccountChoice: true);
      await c.read(authControllerProvider.notifier).chooseAccount('m1');
      expect(c.read(authControllerProvider).needsAccountChoice, isFalse);
      expect(authApi.switched, isEmpty);
    });

    test('unsent offline check-ins block a switch', () async {
      final c = await twoAccounts();
      await queue.enqueue(
        PendingPunch(
          clientPunchId: 'p1',
          type: 'in',
          payload: const {'deviceId': 'd'},
          queuedAt: DateTime(2026, 10, 10, 9),
        ),
      );
      await expectLater(
        c.read(authControllerProvider.notifier).switchTo('m2'),
        throwsA(isA<PendingPunchesException>().having((e) => e.count, 'count', 1)),
      );
      expect(authApi.switched, isEmpty);
    });
  });

  group('never stuck', () {
    test('an account change from a refresh reloads the session and leaves a notice', () async {
      await TokenStorage(store).saveTokens(accessToken: 'a', refreshToken: 'r');
      final c = make();
      addTearDown(c.dispose);
      await settle(c);
      meApi.response = {
        'user': {'id': 'u1', 'phone': '9876543210', 'name': 'Sita', 'role': 'owner', 'companyId': 'c9'},
        'company': {'id': 'c9', 'name': 'Sita Boutique'},
        'employee': null,
        'endedNotices': [
          {'id': 'm1', 'companyName': 'Shop', 'endedReason': 'removed', 'endedAt': '2026-10-03T10:00:00Z'},
        ],
      };
      c.read(authControllerProvider.notifier).onAccountChanged({
        'kind': 'ended',
        'companyName': 'Shop',
        'role': 'owner',
      });
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final s = c.read(authControllerProvider);
      expect(s.company?.name, 'Sita Boutique');
      expect(s.notice?.companyName, 'Shop');
      expect(s.endedNotices.single.reason, 'removed');
      c.read(authControllerProvider.notifier).clearNotice();
      expect(c.read(authControllerProvider).notice, isNull);
    });

    test('phone-locked staff accounts come through /me', () async {
      await TokenStorage(store).saveTokens(accessToken: 'a', refreshToken: 'r');
      meApi.response = {
        'user': {'id': 'u1', 'phone': '9876543210', 'name': 'Sita', 'role': 'owner', 'companyId': null},
        'company': null,
        'employee': null,
        'memberships': [
          {..._membership('m1', 'Shop', 'employee'), 'lockedToOtherPhone': true},
        ],
        'blockedAccounts': [
          {..._membership('m1', 'Shop', 'employee'), 'lockedToOtherPhone': true},
        ],
      };
      final c = make();
      addTearDown(c.dispose);
      final s = await settle(c);
      expect(s.needsCompanySetup, isTrue);
      expect(s.blockedAccounts.single.companyName, 'Shop');
      expect(s.memberships.single.lockedToOtherPhone, isTrue);
    });
  });

  test('a long-idle number on a new phone pauses login with "Is this you?"', () async {
    final c = make();
    addTearDown(c.dispose);
    await settle(c);
    authApi.verifyResponse = {
      'identityCheck': {'token': 'tok-123456789012345678901', 'maskedName': 'R*** K***'},
    };
    final check = await c.read(authControllerProvider.notifier).verifyOtp('9876543210', '123456');
    expect(check?.maskedName, 'R*** K***');
    expect(await TokenStorage(store).readAccessToken(), isNull);
    meApi.response = {
      'user': {'id': 'u9', 'phone': '9876543210', 'name': '', 'role': 'owner', 'companyId': null},
      'company': null,
      'employee': null,
    };
    await c.read(authControllerProvider.notifier).answerIdentity(check!.token, isMe: false);
    expect(accountsApi.answers, [false]);
    expect(await TokenStorage(store).readAccessToken(), 'a3');
    expect(c.read(authControllerProvider).needsCompanySetup, isTrue);
  });
}
