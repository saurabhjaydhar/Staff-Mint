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

  // ---- Staff (or, with [employeeId], the owner doing the steps with someone who has no smartphone)
  String _steps(String? employeeId) =>
      employeeId == null ? '/verification/mine' : '/verification/employees/$employeeId/on-behalf';

  Future<MyVerification> mine({String? employeeId}) async =>
      MyVerification.fromJson(asMap(await _c.get(_steps(employeeId))));

  Future<MyVerification> consent() async => MyVerification.fromJson(asMap(await _c.post('/verification/mine/consent')));

  /// They agreed on paper: the owner adds a photo of the signed slip.
  Future<MyVerification> consentOnPaper(String employeeId, DocFile slip) async => MyVerification.fromJson(
    asMap(await _c.post('${_steps(employeeId)}/consent', body: {'staffAgreed': true, 'slip': slip.toJson()})),
  );

  Future<MyVerification> aadhaarOtp(String aadhaar, {String? employeeId}) async =>
      MyVerification.fromJson(asMap(await _c.post('${_steps(employeeId)}/aadhaar/otp', body: {'aadhaar': aadhaar})));

  Future<MyVerification> aadhaarVerify(String otp, {String? employeeId}) async =>
      MyVerification.fromJson(asMap(await _c.post('${_steps(employeeId)}/aadhaar/verify', body: {'otp': otp})));

  Future<MyVerification> pan(String pan, {String? employeeId}) async =>
      MyVerification.fromJson(asMap(await _c.post('${_steps(employeeId)}/pan', body: {'pan': pan})));

  /// No account given: checks the salary account on file.
  Future<MyVerification> bank({String? accountNumber, String? ifsc, String? employeeId}) async =>
      MyVerification.fromJson(
        asMap(await _c.post('${_steps(employeeId)}/bank', body: {'accountNumber': ?accountNumber, 'ifsc': ?ifsc})),
      );

  /// Driving licence number and date of birth ("1995-04-12").
  Future<MyVerification> dl(String number, String dob, {String? employeeId}) async =>
      MyVerification.fromJson(asMap(await _c.post('${_steps(employeeId)}/dl', body: {'number': number, 'dob': dob})));

  Future<MyVerification> voter(String epic, {String? employeeId}) async =>
      MyVerification.fromJson(asMap(await _c.post('${_steps(employeeId)}/voter', body: {'epic': epic})));

  /// No UAN given: checks the one in their profile.
  Future<MyVerification> uan({String? uan, String? employeeId}) async =>
      MyVerification.fromJson(asMap(await _c.post('${_steps(employeeId)}/uan', body: {'uan': ?uan})));

  /// Selfie (base64 JPEG) matched with the photo on their ID. Not kept.
  Future<MyVerification> face(String selfie, {String? employeeId}) async =>
      MyVerification.fromJson(asMap(await _c.post('${_steps(employeeId)}/face', body: {'selfie': selfie})));

  /// A 5-minute link to the documents check report (PDF).
  Future<String> reportUrl(String employeeId) async =>
      asString(asMap(await _c.post('/verification/employees/$employeeId/report/open'))['url']);

  /// A short link to the slip they signed.
  Future<String> slipUrl(String employeeId) async =>
      asString(asMap(await _c.post('/verification/employees/$employeeId/slip/open'))['url']);

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
