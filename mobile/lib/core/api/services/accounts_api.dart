import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';
import 'auth_api.dart';

/// Account-level actions (PRD F14): leave, close/restore, device change,
/// accountants and staff invites.
class AccountsApi {
  AccountsApi(this._c);
  final ApiClient _c;

  Future<AuthResult> leave(String membershipId, {required String deviceId, String? refreshToken}) async =>
      AuthResult.fromJson(
        asMap(
          await _c.post(
            '/me/accounts/$membershipId/leave',
            body: {'deviceId': deviceId, 'refreshToken': ?refreshToken},
          ),
        ),
      );

  Future<void> dismissNotice(String membershipId) async => _c.post('/me/notices/$membershipId/dismiss');

  Future<AuthResult> restore(String companyId, {required String deviceId, String? refreshToken}) async =>
      AuthResult.fromJson(
        asMap(
          await _c.post(
            '/me/businesses/$companyId/restore',
            body: {'deviceId': deviceId, 'refreshToken': ?refreshToken},
          ),
        ),
      );

  Future<AuthResult> closeBusiness(String confirmName, {required String deviceId, String? refreshToken}) async =>
      AuthResult.fromJson(
        asMap(
          await _c.post(
            '/company/close',
            body: {'confirmName': confirmName, 'deviceId': deviceId, 'refreshToken': ?refreshToken},
          ),
        ),
      );

  /// pending | not_needed
  Future<String> requestDevice(String membershipId, {required String deviceId, String? deviceName}) async {
    final d = asMap(
      await _c.post(
        '/me/device-requests',
        body: {'membershipId': membershipId, 'deviceId': deviceId, 'deviceName': ?deviceName},
      ),
    );
    return asString(d['status'], 'pending');
  }

  Future<void> decideDevice(String requestId, {required bool approve}) async =>
      _c.post('/device-requests/$requestId/${approve ? 'approve' : 'reject'}');

  Future<List<Accountant>> accountants() async => asList(await _c.get('/company/accountants'), Accountant.fromJson);

  Future<void> addAccountant({required String phone, required String name}) async =>
      _c.post('/company/accountants', body: {'phone': phone, 'name': name});

  Future<void> removeAccountant(String id) async => _c.delete('/company/accountants/$id');

  Future<DateTime?> invite(String employeeId) async =>
      asDateTimeOrNull(asMap(await _c.post('/employees/$employeeId/invite'))['invitedAt']);
}
