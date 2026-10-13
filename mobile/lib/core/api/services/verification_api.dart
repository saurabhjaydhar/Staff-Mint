import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';

class VerificationApi {
  VerificationApi(this._c);
  final ApiClient _c;

  // ---- Owner
  Future<OwnerVerification> forEmployee(String employeeId) async =>
      OwnerVerification.fromJson(asMap(await _c.get('/verification/employees/$employeeId')));

  Future<OwnerVerification> request(String employeeId, List<String> kinds) async =>
      OwnerVerification.fromJson(asMap(await _c.post('/verification/employees/$employeeId', body: {'kinds': kinds})));

  Future<OwnerVerification> cancel(String employeeId) async =>
      OwnerVerification.fromJson(asMap(await _c.delete('/verification/employees/$employeeId')));

  Future<OwnerVerification> accept(String checkId, String reason) async => OwnerVerification.fromJson(
    asMap(await _c.post('/verification/checks/$checkId/accept', body: {'reason': reason})),
  );

  Future<OwnerVerification> askAgain(String checkId) async =>
      OwnerVerification.fromJson(asMap(await _c.post('/verification/checks/$checkId/ask-again')));

  // ---- Staff
  Future<MyVerification> mine() async => MyVerification.fromJson(asMap(await _c.get('/verification/mine')));

  Future<MyVerification> consent() async => MyVerification.fromJson(asMap(await _c.post('/verification/mine/consent')));

  Future<MyVerification> aadhaarOtp(String aadhaar) async =>
      MyVerification.fromJson(asMap(await _c.post('/verification/mine/aadhaar/otp', body: {'aadhaar': aadhaar})));

  Future<MyVerification> aadhaarVerify(String otp) async =>
      MyVerification.fromJson(asMap(await _c.post('/verification/mine/aadhaar/verify', body: {'otp': otp})));

  Future<MyVerification> pan(String pan) async =>
      MyVerification.fromJson(asMap(await _c.post('/verification/mine/pan', body: {'pan': pan})));

  /// No account given: checks the salary account on file.
  Future<MyVerification> bank({String? accountNumber, String? ifsc}) async => MyVerification.fromJson(
    asMap(await _c.post('/verification/mine/bank', body: {'accountNumber': ?accountNumber, 'ifsc': ?ifsc})),
  );

  // ---- Documents
  Future<StaffDocs> documentsFor(String employeeId) async =>
      StaffDocs.fromJson(asMap(await _c.get('/verification/employees/$employeeId/documents')));

  Future<StaffDocs> myDocuments() async => StaffDocs.fromJson(asMap(await _c.get('/verification/mine/documents')));

  /// [employeeId] null: the staff member adds their own. Otherwise the owner adds it for them (with consent).
  Future<StaffDoc> addDocument({
    String? employeeId,
    required String kind,
    String? label,
    String? number,
    String? expiresOn,
    required List<DocFile> files,
    bool staffAgreed = false,
    DocFile? slip,
  }) async {
    final body = <String, dynamic>{
      'kind': kind,
      'label': ?label,
      'number': ?number,
      'expiresOn': ?expiresOn,
      'files': [for (final f in files) f.toJson()],
      if (employeeId != null) 'staffAgreed': staffAgreed,
      if (employeeId != null && slip != null) 'slip': slip.toJson(),
    };
    final path = employeeId == null ? '/verification/mine/documents' : '/verification/employees/$employeeId/documents';
    return StaffDoc.fromJson(asMap(await _c.post(path, body: body)));
  }

  Future<StaffDoc> updateDocument(String id, {String? expiresOn}) async =>
      StaffDoc.fromJson(asMap(await _c.patch('/verification/documents/$id', body: {'expiresOn': expiresOn})));

  Future<void> removeDocument(String id) async => _c.delete('/verification/documents/$id');

  Future<OpenedDoc> openDocument(String id) async =>
      OpenedDoc.fromJson(asMap(await _c.post('/verification/documents/$id/open')));
}
