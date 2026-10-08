import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';

class PayrollApi {
  PayrollApi(this._c);
  final ApiClient _c;

  Future<List<PayrollRun>> runs({String? month}) async =>
      asList(await _c.get('/payroll/runs', query: {'month': month}), PayrollRun.fromJson);

  /// Creates or recomputes the draft for [month].
  Future<PayrollRun> prepare(String month) async =>
      PayrollRun.fromJson(asMap(await _c.post('/payroll/runs', body: {'month': month})));

  Future<PayrollRun> get(String id) async => PayrollRun.fromJson(asMap(await _c.get('/payroll/runs/$id')));

  Future<PayrollRun> recompute(String id) async =>
      PayrollRun.fromJson(asMap(await _c.post('/payroll/runs/$id/recompute')));

  Future<PayrollRun> approve(String id) async => PayrollRun.fromJson(asMap(await _c.post('/payroll/runs/$id/approve')));

  Future<PayrollRun> markPaid(String id) async =>
      PayrollRun.fromJson(asMap(await _c.post('/payroll/runs/$id/mark-paid')));

  Future<PayrollRun> revise(String id) async => PayrollRun.fromJson(asMap(await _c.post('/payroll/runs/$id/revise')));

  Future<List<Payslip>> payslips({String? month, String? employeeId}) async =>
      asList(await _c.get('/payslips', query: {'month': month, 'employeeId': employeeId}), Payslip.fromJson);

  Future<Payslip> payslip(String id) async => Payslip.fromJson(asMap(await _c.get('/payslips/$id')));

  Future<PayslipExplanation> explain(String id) async =>
      PayslipExplanation.fromJson(asMap(await _c.get('/payslips/$id/explain')));

  Future<int> sendPayslips(String runId, {List<String>? payslipIds}) async {
    final d = asMap(await _c.post('/payslips/send', body: {'runId': runId, 'payslipIds': ?payslipIds}));
    return asInt(d['queued']);
  }
}
