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
}
