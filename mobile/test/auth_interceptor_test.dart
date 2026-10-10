import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/api/api_client.dart';
import 'package:staffmint/core/api/api_exception.dart';
import 'package:staffmint/core/storage/key_value_store.dart';
import 'package:staffmint/core/storage/token_storage.dart';

import 'helpers/fake_adapter.dart';

Map<String, Object?> _err(String code) => {
  'error': {'code': code, 'message': code},
};

void main() {
  late TokenStorage tokens;
  late int refreshCalls;
  late bool expired;

  setUp(() async {
    tokens = TokenStorage(MemoryKeyValueStore());
    await tokens.saveTokens(accessToken: 'old-access', refreshToken: 'refresh-1');
    refreshCalls = 0;
    expired = false;
  });

  ApiClient client(FakeAdapter adapter) => ApiClient.create(
    tokens: tokens,
    baseUrl: 'http://test/api/v1',
    adapter: adapter,
    languageCode: () => 'hi',
    onSessionExpired: () => expired = true,
  );

  test('attaches bearer token and Accept-Language', () async {
    final adapter = FakeAdapter(
      (o) async => const FakeResponse(200, {
        'data': {'ok': true},
      }),
    );
    final res = await client(adapter).get('/me');
    expect(res, {'ok': true});
    expect(adapter.requests.single.headers['Authorization'], 'Bearer old-access');
    expect(adapter.requests.single.headers['Accept-Language'], 'hi');
  });

  test('refreshes on 401 TOKEN_EXPIRED and replays the request', () async {
    final adapter = FakeAdapter((o) async {
      if (o.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        expect((o.data as Map)['refreshToken'], 'refresh-1');
        return const FakeResponse(200, {
          'data': {'accessToken': 'new-access', 'refreshToken': 'refresh-2'},
        });
      }
      final auth = o.headers['Authorization'];
      if (auth == 'Bearer old-access') return FakeResponse(401, _err('TOKEN_EXPIRED'));
      return const FakeResponse(200, {'data': 'fresh'});
    });

    final res = await client(adapter).get('/dashboard/today');
    expect(res, 'fresh');
    expect(refreshCalls, 1);
    expect(await tokens.readAccessToken(), 'new-access');
    expect(await tokens.readRefreshToken(), 'refresh-2');
    expect(expired, isFalse);
  });

  test('concurrent expired requests share a single refresh', () async {
    final adapter = FakeAdapter((o) async {
      if (o.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return const FakeResponse(200, {
          'data': {'accessToken': 'new-access', 'refreshToken': 'refresh-2'},
        });
      }
      if (o.headers['Authorization'] == 'Bearer old-access') {
        return FakeResponse(401, _err('TOKEN_EXPIRED'));
      }
      return FakeResponse(200, {'data': o.path});
    });
    final c = client(adapter);
    final results = await Future.wait([c.get('/a'), c.get('/b'), c.get('/c')]);
    expect(results, ['/a', '/b', '/c']);
    expect(refreshCalls, 1);
  });

  test('failed refresh clears tokens and reports session expiry', () async {
    final adapter = FakeAdapter((o) async {
      if (o.path.endsWith('/auth/refresh')) return FakeResponse(401, _err('UNAUTHORIZED'));
      return FakeResponse(401, _err('TOKEN_EXPIRED'));
    });
    await expectLater(
      client(adapter).get('/me'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCode.tokenExpired)),
    );
    expect(expired, isTrue);
    expect(await tokens.readAccessToken(), isNull);
  });

  test('other errors pass through untouched (no refresh)', () async {
    final adapter = FakeAdapter((o) async => FakeResponse(422, _err('OUTSIDE_GEOFENCE')));
    await expectLater(
      client(adapter).post('/attendance/check-in', body: {}),
      throwsA(isA<ApiException>().having((e) => e.isOutsideGeofence, 'geofence', isTrue)),
    );
    expect(refreshCalls, 0);
    expect(expired, isFalse);
  });

  test('public endpoints skip the auth header', () async {
    final adapter = FakeAdapter(
      (o) async => const FakeResponse(200, {
        'data': {'requestId': 'r'},
      }),
    );
    await client(adapter).post('/auth/otp/request', body: {'phone': '9876543210'}, auth: false);
    expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('a refresh that moved the phone to another account reports why', () async {
    Map<String, dynamic>? change;
    final adapter = FakeAdapter((o) async {
      if (o.path.endsWith('/auth/refresh')) {
        return const FakeResponse(200, {
          'data': {
            'accessToken': 'new-access',
            'refreshToken': 'refresh-2',
            'accountChange': {'kind': 'ended', 'reason': 'removed', 'companyName': 'Gupta Sweets', 'role': 'owner'},
          },
        });
      }
      if (o.headers['Authorization'] == 'Bearer old-access') {
        return const FakeResponse(401, {
          'error': {
            'code': 'TOKEN_EXPIRED',
            'message': 'Your access to this business changed',
            'details': {'reason': 'account_changed'},
          },
        });
      }
      return const FakeResponse(200, {'data': 'next account'});
    });
    final c = ApiClient.create(
      tokens: tokens,
      baseUrl: 'http://test/api/v1',
      adapter: adapter,
      onSessionExpired: () => expired = true,
      onAccountChanged: (j) => change = j,
    );
    expect(await c.get('/me'), 'next account');
    expect(change?['companyName'], 'Gupta Sweets');
    expect(expired, isFalse);
    expect(await tokens.readRefreshToken(), 'refresh-2');
  });
}
