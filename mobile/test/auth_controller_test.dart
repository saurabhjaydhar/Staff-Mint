import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/api/api_exception.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/me_api.dart';
import 'package:staffmint/core/storage/key_value_store.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/core/storage/token_storage.dart';
import 'package:staffmint/core/utils/json.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';

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

  ProviderContainer make() => ProviderContainer(
    retry: (_, _) => null,
    overrides: [secureStoreProvider.overrideWithValue(store), meApiProvider.overrideWithValue(meApi)],
  );

  Future<SessionState> settle(ProviderContainer c) async {
    c.read(authControllerProvider);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      if (c.read(authControllerProvider).status != SessionStatus.unknown) break;
    }
    return c.read(authControllerProvider);
  }

  setUp(() {
    store = MemoryKeyValueStore();
    meApi = _FakeMeApi();
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
}
