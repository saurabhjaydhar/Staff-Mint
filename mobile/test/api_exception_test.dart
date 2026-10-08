import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/api/api_client.dart';
import 'package:staffmint/core/api/api_exception.dart';
import 'package:staffmint/core/api/services/attendance_api.dart';
import 'package:staffmint/core/models/models.dart';

void main() {
  final req = RequestOptions(path: '/x');

  group('ApiException.fromResponse', () {
    test('parses the standard error envelope', () {
      final e = ApiException.fromResponse(422, {
        'error': {
          'code': 'OUTSIDE_GEOFENCE',
          'message': 'You are 320 m away from the shop',
          'details': {'distanceM': 320},
        },
      });
      expect(e.code, ApiErrorCode.outsideGeofence);
      expect(e.isOutsideGeofence, isTrue);
      expect(e.statusCode, 422);
      expect(e.message, 'You are 320 m away from the shop');
      expect((e.details as Map)['distanceM'], 320);
      expect(e.isRetryable, isFalse);
    });

    test('decodes a JSON string body', () {
      final e = ApiException.fromResponse(402, '{"error":{"code":"PLAN_LIMIT","message":"Upgrade to add more staff"}}');
      expect(e.code, ApiErrorCode.planLimit);
      expect(e.isPlanError, isTrue);
    });

    test('falls back to a status-based code for non-envelope bodies', () {
      expect(ApiException.fromResponse(404, '<html>').code, ApiErrorCode.notFound);
      expect(ApiException.fromResponse(503, null).code, ApiErrorCode.internal);
      expect(ApiException.fromResponse(503, null).isRetryable, isTrue);
      expect(ApiException.fromResponse(401, {}).code, ApiErrorCode.unauthorized);
    });
  });

  group('ApiException.fromDio', () {
    test('connection problems are network errors', () {
      for (final type in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
      ]) {
        final e = ApiException.fromDio(DioException(requestOptions: req, type: type));
        expect(e.isNetwork, isTrue, reason: '$type');
        expect(e.isRetryable, isTrue);
      }
    });

    test('SocketException wrapped in unknown is a network error', () {
      final e = ApiException.fromDio(
        DioException(
          requestOptions: req,
          type: DioExceptionType.unknown,
          error: const SocketException('Failed host lookup'),
        ),
      );
      expect(e.isNetwork, isTrue);
    });

    test('bad responses parse the body', () {
      final e = ApiException.fromDio(
        DioException(
          requestOptions: req,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: req,
            statusCode: 401,
            data: {
              'error': {'code': 'TOKEN_EXPIRED', 'message': 'expired'},
            },
          ),
        ),
      );
      expect(e.isTokenExpired, isTrue);
      expect(e.statusCode, 401);
    });
  });

  group('ApiClient.unwrap', () {
    test('returns data from the success envelope', () {
      expect(
        ApiClient.unwrap({
          'data': [1, 2],
        }),
        [1, 2],
      );
      expect(ApiClient.unwrap({'data': null}), isNull);
    });

    test('throws on an error envelope with 2xx', () {
      expect(
        () => ApiClient.unwrap({
          'error': {'code': 'CONFLICT', 'message': 'dup'},
        }),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'CONFLICT')),
      );
    });
  });

  group('model parsing', () {
    test('PunchSyncResult accepts object or string errors', () {
      final a = PunchSyncResult.fromJson({
        'clientPunchId': 'a',
        'ok': false,
        'error': {'code': 'OUTSIDE_GEOFENCE', 'message': 'far'},
      });
      expect(a.errorCode, 'OUTSIDE_GEOFENCE');
      expect(a.errorMessage, 'far');
      final b = PunchSyncResult.fromJson({'clientPunchId': 'b', 'ok': false, 'error': 'VALIDATION_ERROR'});
      expect(b.errorCode, 'VALIDATION_ERROR');
      final c = PunchSyncResult.fromJson({'clientPunchId': 'c', 'ok': false, 'error': 'Something broke'});
      expect(c.errorCode, isNull);
      expect(c.errorMessage, 'Something broke');
    });

    test('PayrollRun parses totals, anomalies and payslips', () {
      final run = PayrollRun.fromJson({
        'id': 'r1',
        'month': '2026-09',
        'revision': 2,
        'status': 'draft',
        'totals': {'grossPaise': 3000000, 'deductionsPaise': 500000, 'netPaise': 2500000, 'employees': 2},
        'anomalies': [
          {'employeeId': 'e1', 'employeeName': 'Ramesh', 'code': 'NEGATIVE_NET', 'message': 'Net is negative'},
        ],
        'payslips': [
          {
            'id': 'p1',
            'employeeId': 'e1',
            'employeeName': 'Ramesh',
            'month': '2026-09',
            'payableDays': 25.5,
            'lines': [
              {
                'code': 'BASE',
                'kind': 'earning',
                'label': 'Salary',
                'amountPaise': 1200000,
                'explanation': '12000 ÷ 30 × 25.5',
              },
            ],
            'netPaise': 1020000,
          },
        ],
      });
      expect(run.netPaise, 2500000);
      expect(run.employees, 2);
      expect(run.anomaliesFor('e1'), hasLength(1));
      expect(run.payslips!.single.payableDays, 25.5);
      expect(run.payslips!.single.lines.single.explanation, contains('25.5'));
    });

    test('Attendance sorts punches and finds first in / last out', () {
      final a = Attendance.fromJson({
        'id': 'a1',
        'employeeId': 'e1',
        'date': '2026-10-08',
        'status': 'present',
        'punches': [
          {'id': '2', 'type': 'out', 'clientTime': '2026-10-08T13:30:00Z'},
          {
            'id': '1',
            'type': 'in',
            'clientTime': '2026-10-08T03:35:00Z',
            'geo': {'lat': 28.6, 'lng': 77.2, 'accuracyM': 12},
          },
        ],
        'lateMinutes': '5',
      });
      expect(a.firstIn!.id, '1');
      expect(a.lastOut!.id, '2');
      expect(a.lateMinutes, 5);
      expect(a.firstIn!.geo!.accuracyM, 12);
    });

    test('Employee consent and Company settings defaults', () {
      final e = Employee.fromJson({
        'id': 'e1',
        'name': 'Sita',
        'phone': '9876543210',
        'consent': {'location': true, 'at': '2026-10-01T00:00:00Z'},
      });
      expect(e.locationConsent, isTrue);
      final c = Company.fromJson({
        'id': 'c1',
        'name': 'Shop',
        'settings': {'graceMinutes': 10},
      });
      expect(c.settings.graceMinutes, 10);
      expect(c.settings.selfieRequired, isTrue);
      expect(c.settings.missingCheckoutPolicy, 'half_day');
    });
  });
}
