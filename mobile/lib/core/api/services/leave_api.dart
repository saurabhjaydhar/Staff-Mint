import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';

class LeaveApi {
  LeaveApi(this._c);
  final ApiClient _c;

  Future<List<Leave>> list({String? status, String? employeeId}) async =>
      asList(await _c.get('/leaves', query: {'status': status, 'employeeId': employeeId}), Leave.fromJson);

  Future<Leave> apply({
    required String type,
    required String from,
    required String to,
    bool halfDay = false,
    String? reason,
    String? employeeId,
  }) async => Leave.fromJson(
    asMap(
      await _c.post(
        '/leaves',
        body: {
          'type': type,
          'from': from,
          'to': to,
          'halfDay': halfDay,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
          'employeeId': ?employeeId,
        },
      ),
    ),
  );

  /// [asUnpaid]: approve as unpaid leave (no paid/sick leave left).
  Future<Leave> decide(String id, {required bool approve, String? note, bool asUnpaid = false}) async => Leave.fromJson(
    asMap(
      await _c.post(
        '/leaves/$id/decision',
        body: {
          'decision': approve ? 'approved' : 'rejected',
          if (note != null && note.isNotEmpty) 'note': note,
          if (approve && asUnpaid) 'asUnpaid': true,
        },
      ),
    ),
  );

  Future<Leave> cancel(String id) async => Leave.fromJson(asMap(await _c.post('/leaves/$id/cancel')));

  Future<List<LeaveBalance>> balances({String? employeeId, int? year}) async =>
      asList(await _c.get('/leave-balances', query: {'employeeId': employeeId, 'year': year}), LeaveBalance.fromJson);

  Future<LeaveBalance> setBalance(String employeeId, {required int year, required num paid, required num sick}) async =>
      LeaveBalance.fromJson(
        asMap(await _c.put('/leave-balances/$employeeId', body: {'year': year, 'paid': paid, 'sick': sick})),
      );
}
