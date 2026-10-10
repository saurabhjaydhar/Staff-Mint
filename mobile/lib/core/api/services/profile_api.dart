import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';

class ProfileApi {
  ProfileApi(this._c);
  final ApiClient _c;

  Future<Profile> get() async => Profile.fromJson(asMap(await _c.get('/me/profile')));

  /// Any of name, email (null clears), language, emergencyContact (null clears).
  Future<Profile> update(Json patch) async => Profile.fromJson(asMap(await _c.patch('/me/profile', body: patch)));

  Future<Profile> setPhoto(String base64Jpeg) async =>
      Profile.fromJson(asMap(await _c.put('/me/photo', body: {'photoBase64': base64Jpeg})));

  Future<Profile> removePhoto() async => Profile.fromJson(asMap(await _c.delete('/me/photo')));

  Future<BankInfo?> setBank(Json bank) async => BankInfo.fromJsonOrNull(await _c.put('/me/bank', body: bank));

  Future<void> removeBank() async => _c.delete('/me/bank');

  /// Owner fills in a staff member's salary account.
  Future<BankInfo?> setStaffBank(String employeeId, Json bank) async =>
      BankInfo.fromJsonOrNull(await _c.put('/employees/$employeeId/bank', body: bank));

  /// Sends an OTP to the new number. Returns the test code in dev mode.
  Future<String?> requestPhoneChange(String phone) async =>
      asStringOrNull(asMap(await _c.post('/me/phone/request', body: {'phone': phone}))['devCode']);

  Future<Profile> verifyPhoneChange(String phone, String code) async =>
      Profile.fromJson(asMap(await _c.post('/me/phone/verify', body: {'phone': phone, 'code': code})));

  Future<void> logoutEverywhere() async => _c.post('/me/logout-all');
}
