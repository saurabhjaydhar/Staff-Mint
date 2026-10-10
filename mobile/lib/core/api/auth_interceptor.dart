import 'package:dio/dio.dart';

import '../storage/token_storage.dart';
import '../utils/json.dart';
import 'api_exception.dart';

/// Attaches the bearer token and `Accept-Language`, and transparently refreshes
/// the access token when the API answers `401 TOKEN_EXPIRED`.
///
/// Concurrent requests that expire at the same time share one refresh call
/// (refresh tokens rotate, so refreshing twice would log the user out).
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.tokens,
    required this.dio,
    required this.refreshDio,
    this.languageCode,
    this.onSessionExpired,
    this.onAccountChanged,
  });

  /// Request option `extra` keys.
  static const skipAuthKey = 'skipAuth';
  static const retriedKey = 'authRetried';

  final TokenStorage tokens;

  /// The main client — used to replay the original request.
  final Dio dio;

  /// A bare client without this interceptor, used for `/auth/refresh`.
  final Dio refreshDio;
  final String Function()? languageCode;
  final void Function()? onSessionExpired;

  /// The refresh moved this phone to another account (access ended or role
  /// changed): the app reloads the session and says why.
  final void Function(Json change)? onAccountChanged;

  Future<String?>? _refreshing;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final lang = languageCode?.call();
    if (lang != null) options.headers['Accept-Language'] = lang;
    if (options.extra[skipAuthKey] != true) {
      final token = await tokens.readAccessToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final options = err.requestOptions;
    final code = _errorCode(response?.data);
    final hadAuth = options.headers.containsKey('Authorization');

    if (response?.statusCode == 401 &&
        code == ApiErrorCode.tokenExpired &&
        options.extra[skipAuthKey] != true &&
        options.extra[retriedKey] != true) {
      try {
        final newToken = await refreshAccessToken();
        if (newToken == null) {
          return handler.next(err);
        }
        options.headers['Authorization'] = 'Bearer $newToken';
        options.extra[retriedKey] = true;
        final retried = await dio.fetch<dynamic>(options);
        return handler.resolve(retried);
      } on DioException catch (e) {
        return handler.next(e);
      }
    }

    if (response?.statusCode == 401 &&
        code == ApiErrorCode.unauthorized &&
        hadAuth &&
        options.extra[skipAuthKey] != true) {
      await tokens.clear();
      onSessionExpired?.call();
    }
    handler.next(err);
  }

  /// Refreshes once even when called concurrently. Returns the new access
  /// token, or null when the session is no longer valid (user logged out).
  /// Network failures are rethrown so callers can treat them as offline.
  Future<String?> refreshAccessToken() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await tokens.readRefreshToken();
    if (refreshToken == null) {
      _expire();
      return null;
    }
    try {
      final res = await refreshDio.post<dynamic>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: {skipAuthKey: true}),
      );
      final data = asMap(asMap(res.data)['data']);
      final access = asStringOrNull(data['accessToken']);
      final refresh = asStringOrNull(data['refreshToken']);
      if (access == null || refresh == null) {
        _expire();
        return null;
      }
      await tokens.saveTokens(accessToken: access, refreshToken: refresh);
      final change = data['accountChange'];
      if (change is Map) onAccountChanged?.call(asMap(change));
      return access;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != null && status >= 400 && status < 500) {
        await tokens.clear();
        _expire();
        return null;
      }
      rethrow;
    }
  }

  void _expire() => onSessionExpired?.call();

  static String? _errorCode(Object? body) {
    if (body is Map) {
      final err = body['error'];
      if (err is Map) return err['code']?.toString();
    }
    return null;
  }
}
