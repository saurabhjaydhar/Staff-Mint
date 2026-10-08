import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';

class OtpRequestResult {
  const OtpRequestResult({required this.requestId, required this.expiresInSec, this.devCode});
  final String requestId;
  final int expiresInSec;
  final String? devCode;

  factory OtpRequestResult.fromJson(Json j) => OtpRequestResult(
    requestId: asString(j['requestId']),
    expiresInSec: asInt(j['expiresInSec'], 300),
    devCode: asStringOrNull(j['devCode']),
  );
}

class AuthResult {
  const AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    required this.needsCompanySetup,
  });
  final String accessToken;
  final String refreshToken;
  final User user;
  final bool needsCompanySetup;

  factory AuthResult.fromJson(Json j) => AuthResult(
    accessToken: asString(j['accessToken']),
    refreshToken: asString(j['refreshToken']),
    user: User.fromJson(asMap(j['user'])),
    needsCompanySetup: asBool(j['needsCompanySetup']),
  );
}

class AuthApi {
  AuthApi(this._c);
  final ApiClient _c;

  Future<OtpRequestResult> requestOtp(String phone, {String channel = 'sms'}) async {
    final d = await _c.post('/auth/otp/request', body: {'phone': phone, 'channel': channel}, auth: false);
    return OtpRequestResult.fromJson(asMap(d));
  }

  Future<AuthResult> verifyOtp({
    required String phone,
    required String code,
    required String deviceId,
    String? deviceName,
  }) async {
    final d = await _c.post(
      '/auth/otp/verify',
      body: {'phone': phone, 'code': code, 'deviceId': deviceId, 'deviceName': ?deviceName},
      auth: false,
    );
    return AuthResult.fromJson(asMap(d));
  }

  Future<void> logout(String refreshToken) async {
    await _c.post('/auth/logout', body: {'refreshToken': refreshToken}, auth: false);
  }
}
