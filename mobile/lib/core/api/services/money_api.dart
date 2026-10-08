import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';

class MoneyApi {
  MoneyApi(this._c);
  final ApiClient _c;

  Future<List<Advance>> advances({String? employeeId, String? status}) async =>
      asList(await _c.get('/advances', query: {'employeeId': employeeId, 'status': status}), Advance.fromJson);

  Future<Advance> addAdvance({
    required String employeeId,
    required int amountPaise,
    required String date,
    required String mode,
    int? installments,
    String? note,
  }) async => Advance.fromJson(
    asMap(
      await _c.post(
        '/advances',
        body: {
          'employeeId': employeeId,
          'amountPaise': amountPaise,
          'date': date,
          'mode': mode,
          'installments': ?installments,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      ),
    ),
  );

  Future<Advance> skipMonth(String id, String month) async =>
      Advance.fromJson(asMap(await _c.post('/advances/$id/skip', body: {'month': month})));

  Future<List<Adjustment>> adjustments({String? month, String? employeeId}) async =>
      asList(await _c.get('/adjustments', query: {'month': month, 'employeeId': employeeId}), Adjustment.fromJson);

  Future<Adjustment> addAdjustment({
    required String employeeId,
    required String month,
    required String type,
    required int amountPaise,
    String? note,
  }) async => Adjustment.fromJson(
    asMap(
      await _c.post(
        '/adjustments',
        body: {
          'employeeId': employeeId,
          'month': month,
          'type': type,
          'amountPaise': amountPaise,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      ),
    ),
  );

  Future<void> deleteAdjustment(String id) async => _c.delete('/adjustments/$id');
}
