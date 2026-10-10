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
    this.memberships = const [],
    this.activeMembershipId,
    this.needsAccountChoice = false,
    this.identityCheck,
  });
  final String accessToken;
  final String refreshToken;
  final User user;
  final bool needsCompanySetup;

  /// Every business this number can open, most recently used first.
  final List<Membership> memberships;
  final String? activeMembershipId;

  /// More than one account: the app asks which one to open.
  final bool needsAccountChoice;

  /// Set instead of a session when the app must ask "Is this you?" first.
  final IdentityCheck? identityCheck;

  factory AuthResult.fromJson(Json j) => AuthResult(
    accessToken: asString(j['accessToken']),
    refreshToken: asString(j['refreshToken']),
    user: j['user'] is Map
        ? User.fromJson(asMap(j['user']))
        : const User(id: '', phone: '', name: '', role: UserRole.owner),
    needsCompanySetup: asBool(j['needsCompanySetup']),
    memberships: asList(j['memberships'], Membership.fromJson),
    activeMembershipId: asStringOrNull(j['activeMembershipId']),
    needsAccountChoice: asBool(j['needsAccountChoice']),
    identityCheck: IdentityCheck.fromJsonOrNull(j['identityCheck']),
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

  /// Fresh tokens; the server re-checks whether this number has been added as staff.
  Future<({String accessToken, String refreshToken})> refresh(String refreshToken) async {
    final d = asMap(await _c.post('/auth/refresh', body: {'refreshToken': refreshToken}, auth: false));
    return (accessToken: asString(d['accessToken']), refreshToken: asString(d['refreshToken']));
  }

  /// Opens another of this person's businesses on this device. The old
  /// refresh token is retired server-side.
  Future<AuthResult> switchAccount({
    required String membershipId,
    required String deviceId,
    String? refreshToken,
  }) async {
    final d = await _c.post(
      '/auth/switch',
      body: {'membershipId': membershipId, 'deviceId': deviceId, 'refreshToken': ?refreshToken},
    );
    return AuthResult.fromJson(asMap(d));
  }

  Future<void> logout(String refreshToken) async {
    await _c.post('/auth/logout', body: {'refreshToken': refreshToken}, auth: false);
  }
}
