import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';

class BulkCreateResult {
  const BulkCreateResult({required this.created, required this.skipped});
  final List<Employee> created;
  final List<({String phone, String reason})> skipped;
}

class EmployeesApi {
  EmployeesApi(this._c);
  final ApiClient _c;

  Future<List<Employee>> list({String? search, String status = 'active', String? branchId}) async => asList(
    await _c.get('/employees', query: {'search': search, 'status': status, 'branchId': branchId}),
    Employee.fromJson,
  );

  Future<Employee> create(NewEmployee e) async =>
      Employee.fromJson(asMap(await _c.post('/employees', body: e.toJson())));

  Future<BulkCreateResult> bulkCreate(List<NewEmployee> list) async {
    final d = asMap(await _c.post('/employees/bulk', body: {'employees': list.map((e) => e.toJson()).toList()}));
    return BulkCreateResult(
      created: asList(d['created'], Employee.fromJson),
      skipped: asList(d['skipped'], (j) => (phone: asString(j['phone']), reason: asString(j['reason']))),
    );
  }

  Future<Employee> get(String id) async => Employee.fromJson(asMap(await _c.get('/employees/$id')));

  Future<FaceInfo> face(String id) async => FaceInfo.fromJson(asMap(await _c.get('/employees/$id/face')));

  Future<FaceInfo> approveFace(String id) async =>
      FaceInfo.fromJson(asMap(await _c.post('/employees/$id/face/approve')));

  /// Deletes the photo; the staff member is asked to set it up again.
  Future<FaceInfo> resetFace(String id) async => FaceInfo.fromJson(asMap(await _c.delete('/employees/$id/face')));

  Future<Employee> update(String id, Json partial) async =>
      Employee.fromJson(asMap(await _c.patch('/employees/$id', body: partial)));

  /// Employee ID, UAN, ESIC, PAN and PF/ESI exemption for the salary slip (owner only).
  /// Make someone a manager (or back to staff). [allBranches]: see every branch, not just their own.
  Future<Employee> setRole(String id, String role, {bool allBranches = false}) async => Employee.fromJson(
    asMap(await _c.post('/employees/$id/role', body: {'role': role, if (allBranches) 'allBranches': true})),
  );

  Future<EmployeeStatutory> updateStatutory(String id, Json partial) async =>
      EmployeeStatutory.fromJson(asMap(await _c.patch('/employees/$id/statutory', body: partial)));

  Future<Employee> deactivate(String id, {String? reason}) async => Employee.fromJson(
    asMap(
      await _c.post('/employees/$id/deactivate', body: {if (reason != null && reason.isNotEmpty) 'reason': reason}),
    ),
  );

  Future<Employee> resetDevice(String id) async =>
      Employee.fromJson(asMap(await _c.post('/employees/$id/reset-device')));
}
