import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../utils/json.dart';

/// Error codes defined by the API contract plus client-side codes.
class ApiErrorCode {
  ApiErrorCode._();
  static const validation = 'VALIDATION_ERROR';
  static const unauthorized = 'UNAUTHORIZED';
  static const tokenExpired = 'TOKEN_EXPIRED';
  static const forbidden = 'FORBIDDEN';
  static const notFound = 'NOT_FOUND';
  static const conflict = 'CONFLICT';
  static const rateLimited = 'RATE_LIMITED';
  static const planLimit = 'PLAN_LIMIT';
  static const featureNotInPlan = 'FEATURE_NOT_IN_PLAN';
  static const deviceNotBound = 'DEVICE_NOT_BOUND';
  static const outsideGeofence = 'OUTSIDE_GEOFENCE';
  static const otpInvalid = 'OTP_INVALID';
  static const companySetupRequired = 'COMPANY_SETUP_REQUIRED';
  static const internal = 'INTERNAL';

  // Client-side only.
  static const network = 'NETWORK_ERROR';
  static const cancelled = 'CANCELLED';
  static const unknown = 'UNKNOWN';
}

/// A normalised error from the StaffMint API (or the network below it).
class ApiException implements Exception {
  const ApiException({required this.code, required this.message, this.statusCode, this.details});

  final String code;
  final String message;
  final int? statusCode;
  final Object? details;

  /// True when the request never reached the server (offline, DNS, timeout).
  bool get isNetwork => code == ApiErrorCode.network;
  bool get isTokenExpired => code == ApiErrorCode.tokenExpired;
  bool get isUnauthorized => code == ApiErrorCode.unauthorized;
  bool get isOutsideGeofence => code == ApiErrorCode.outsideGeofence;
  bool get isPlanError => code == ApiErrorCode.planLimit || code == ApiErrorCode.featureNotInPlan;

  /// Server errors (5xx / rate limit) are worth retrying later.
  bool get isRetryable =>
      isNetwork ||
      code == ApiErrorCode.rateLimited ||
      code == ApiErrorCode.internal ||
      (statusCode != null && statusCode! >= 500);

  factory ApiException.network([String message = 'Network unavailable']) =>
      ApiException(code: ApiErrorCode.network, message: message);

  /// Parses an error envelope `{ "error": { code, message, details? } }`.
  factory ApiException.fromResponse(int? statusCode, Object? body) {
    Object? decoded = body;
    if (body is String && body.isNotEmpty) {
      try {
        decoded = jsonDecode(body);
      } catch (_) {
        decoded = body;
      }
    }
    if (decoded is Map) {
      final err = decoded['error'];
      if (err is Map) {
        return ApiException(
          code: asString(err['code'], _codeForStatus(statusCode)),
          message: asString(err['message'], 'Request failed'),
          statusCode: statusCode,
          details: err['details'],
        );
      }
      if (err is String) {
        return ApiException(code: _codeForStatus(statusCode), message: err, statusCode: statusCode);
      }
    }
    return ApiException(
      code: _codeForStatus(statusCode),
      message: decoded is String && decoded.isNotEmpty && decoded.length < 300
          ? decoded
          : 'Request failed${statusCode != null ? ' ($statusCode)' : ''}',
      statusCode: statusCode,
    );
  }

  factory ApiException.fromDio(DioException e) {
    final inner = e.error;
    if (inner is ApiException) return inner;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.transformTimeout:
        return ApiException.network(e.message ?? 'Network unavailable');
      case DioExceptionType.cancel:
        return const ApiException(code: ApiErrorCode.cancelled, message: 'Cancelled');
      case DioExceptionType.badResponse:
        return ApiException.fromResponse(e.response?.statusCode, e.response?.data);
      case DioExceptionType.badCertificate:
        return const ApiException(code: ApiErrorCode.network, message: 'Bad certificate');
      case DioExceptionType.unknown:
        if (inner is SocketException || inner is HttpException || inner is HandshakeException) {
          return ApiException.network(inner.toString());
        }
        if (e.response != null) {
          return ApiException.fromResponse(e.response?.statusCode, e.response?.data);
        }
        return ApiException(code: ApiErrorCode.unknown, message: e.message ?? inner?.toString() ?? 'Unknown error');
    }
  }

  static String _codeForStatus(int? status) {
    switch (status) {
      case 400:
        return ApiErrorCode.validation;
      case 401:
        return ApiErrorCode.unauthorized;
      case 402:
        return ApiErrorCode.planLimit;
      case 403:
        return ApiErrorCode.forbidden;
      case 404:
        return ApiErrorCode.notFound;
      case 409:
        return ApiErrorCode.conflict;
      case 429:
        return ApiErrorCode.rateLimited;
      default:
        if (status != null && status >= 500) return ApiErrorCode.internal;
        return ApiErrorCode.unknown;
    }
  }

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
