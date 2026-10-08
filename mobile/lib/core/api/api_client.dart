import 'package:dio/dio.dart';

import '../config/env.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';

/// Thin wrapper around Dio that unwraps the `{ data: ... }` envelope and
/// converts every failure into an [ApiException].
class ApiClient {
  ApiClient(this.dio);

  final Dio dio;

  /// Builds the production client.
  factory ApiClient.create({
    required TokenStorage tokens,
    String baseUrl = Env.apiBaseUrl,
    String Function()? languageCode,
    void Function()? onSessionExpired,
    HttpClientAdapter? adapter,
  }) {
    BaseOptions options() => BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    );
    final dio = Dio(options());
    final refreshDio = Dio(options());
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
      refreshDio.httpClientAdapter = adapter;
    }
    dio.interceptors.add(
      AuthInterceptor(
        tokens: tokens,
        dio: dio,
        refreshDio: refreshDio,
        languageCode: languageCode,
        onSessionExpired: onSessionExpired,
      ),
    );
    return ApiClient(dio);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query, bool auth = true}) =>
      _send(() => dio.get<dynamic>(path, queryParameters: _clean(query), options: _opts(auth)));

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query, bool auth = true}) => _send(
    () => dio.post<dynamic>(
      path,
      data: body ?? const <String, dynamic>{},
      queryParameters: _clean(query),
      options: _opts(auth),
    ),
  );

  Future<dynamic> patch(String path, {Object? body}) => _send(() => dio.patch<dynamic>(path, data: body));

  Future<dynamic> put(String path, {Object? body}) => _send(() => dio.put<dynamic>(path, data: body));

  Future<dynamic> delete(String path) => _send(() => dio.delete<dynamic>(path));

  /// Raw GET returning the full response (used for file downloads).
  Future<Response<dynamic>> getRaw(String path, {Map<String, dynamic>? query, ResponseType? responseType}) async {
    try {
      return await dio.get<dynamic>(
        path,
        queryParameters: _clean(query),
        options: Options(responseType: responseType),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Options? _opts(bool auth) => auth ? null : Options(extra: {AuthInterceptor.skipAuthKey: true});

  static Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) out[k] = v;
    });
    return out;
  }

  static Future<dynamic> _send(Future<Response<dynamic>> Function() fn) async {
    try {
      final res = await fn();
      return unwrap(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Returns `body.data` for the standard envelope, or the body itself.
  static dynamic unwrap(Object? body) {
    if (body is Map && body.containsKey('data')) return body['data'];
    if (body is Map && body['error'] is Map) {
      throw ApiException.fromResponse(null, body);
    }
    return body;
  }
}
