import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';

class ReportsApi {
  ReportsApi(this._c);
  final ApiClient _c;

  /// kind: attendance | salary | advances | late ; format: pdf | xlsx.
  Future<String> reportUrl({required String kind, required String month, required String format}) async {
    final d = asMap(await _c.get('/reports/$kind', query: {'month': month, 'format': format, 'delivery': 'url'}));
    return asString(d['url']);
  }

  /// `GET /export`. The contract returns a zip; we also pass
  /// `delivery=url` (same convention as reports). If the server answers with
  /// JSON `{url}` we return the URL, otherwise the raw zip bytes.
  Future<({String? url, Uint8List? bytes})> export() async {
    final res = await _c.getRaw('/export', query: {'delivery': 'url'}, responseType: ResponseType.bytes);
    final body = res.data;
    final type = res.headers.value(Headers.contentTypeHeader) ?? '';
    if (body is List<int>) {
      final bytes = Uint8List.fromList(body);
      if (type.contains('json')) {
        try {
          final decoded = ApiClient.unwrap(jsonDecode(utf8.decode(bytes)));
          final url = asStringOrNull(asMap(decoded)['url']);
          if (url != null) return (url: url, bytes: null);
        } catch (_) {}
      }
      return (url: null, bytes: bytes);
    }
    return (url: null, bytes: null);
  }
}

class AssistantApi {
  AssistantApi(this._c);
  final ApiClient _c;

  Future<AssistantReply> message({String? text, String? audioBase64, String? audioMime, String? sessionId}) async =>
      AssistantReply.fromJson(
        asMap(
          await _c.post(
            '/assistant/message',
            body: {'text': ?text, 'audioBase64': ?audioBase64, 'audioMime': ?audioMime, 'sessionId': ?sessionId},
          ),
        ),
      );

  /// action: confirm | cancel | choose
  Future<AssistantReply> confirm({required String pendingActionId, required String action, String? optionId}) async =>
      AssistantReply.fromJson(
        asMap(
          await _c.post(
            '/assistant/confirm',
            body: {'pendingActionId': pendingActionId, 'action': action, 'optionId': ?optionId},
          ),
        ),
      );
}

class BillingApi {
  BillingApi(this._c);
  final ApiClient _c;

  Future<List<Plan>> plans() async => asList(await _c.get('/billing/plans', auth: false), Plan.fromJson);

  Future<BillingInfo> subscription() async => BillingInfo.fromJson(asMap(await _c.get('/billing/subscription')));

  Future<String> subscribe(String planCode, String interval) async {
    final d = asMap(await _c.post('/billing/subscribe', body: {'planCode': planCode, 'interval': interval}));
    return asString(d['checkoutUrl']);
  }

  Future<void> cancel() async => _c.post('/billing/cancel');
}

class AuditApi {
  AuditApi(this._c);
  final ApiClient _c;

  Future<List<AuditLog>> list({
    String? entity,
    String? entityId,
    String? category,
    int limit = 50,
    String? before,
  }) async => asList(
    await _c.get(
      '/audit-logs',
      query: {'entity': entity, 'entityId': entityId, 'category': category, 'limit': limit, 'before': before},
    ),
    AuditLog.fromJson,
  );
}
