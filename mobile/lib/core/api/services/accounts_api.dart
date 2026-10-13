import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';
import '../api_exception.dart';
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

  /// Re-sends the app invite to every staff member who hasn't joined, and says per person what happened.
  Future<RemindResult> remindNotJoined() async =>
      RemindResult.fromJson(asMap(await _c.post('/employees/remind-invites')));

  /// One person's invite. Sent a few minutes ago: status `recent` (nothing re-sent).
  Future<RemindResult> inviteOne(Employee e) async {
    Json j;
    String status;
    try {
      j = asMap(await _c.post('/employees/${e.id}/invite'));
      status = asBool(j['delivered'], true) ? 'sent' : 'failed';
    } on ApiException catch (err) {
      if (err.statusCode != 429) rethrow;
      j = asMapOrNull(err.details) ?? const {};
      status = 'recent';
    }
    return RemindResult(
      sent: status == 'sent' ? 1 : 0,
      failed: status == 'failed' ? 1 : 0,
      whatsappConnected: asBool(j['whatsappConnected'], true),
      people: [InvitePerson(name: e.name, phone: e.phone, status: status, shareText: asString(j['shareText']))],
    );
  }

  // ---------------------------------------------------------------- Phase 3

  /// "Is this you?" answer after a paused login (public endpoint).
  Future<AuthResult> answerIdentity(String token, {required bool isMe}) async => AuthResult.fromJson(
    asMap(await _c.post('/auth/identity/${isMe ? 'confirm' : 'reject'}', body: {'token': token}, auth: false)),
  );

  Future<List<OwnerItem>> owners() async => asList(await _c.get('/company/owners'), OwnerItem.fromJson);

  Future<List<OwnerItem>> addOwner({
    required String phone,
    required String name,
    bool canManageBilling = false,
  }) async => asList(
    await _c.post('/company/owners', body: {'phone': phone, 'name': name, 'canManageBilling': canManageBilling}),
    OwnerItem.fromJson,
  );

  Future<List<OwnerItem>> setOwnerBilling(String id, bool allowed) async =>
      asList(await _c.patch('/company/owners/$id', body: {'canManageBilling': allowed}), OwnerItem.fromJson);

  Future<List<OwnerItem>> removeOwner(String id) async =>
      asList(await _c.delete('/company/owners/$id'), OwnerItem.fromJson);

  Future<TransferOffer> startTransfer({required String phone, required String keepAs, required String code}) async =>
      TransferOffer.fromJson(
        asMap(await _c.post('/company/transfer', body: {'phone': phone, 'keepAs': keepAs, 'code': code})),
      );

  Future<TransferOffer?> currentTransfer() async {
    final d = await _c.get('/company/transfer');
    return d is Map ? TransferOffer.fromJson(asMap(d)) : null;
  }

  Future<void> cancelTransfer() async => _c.delete('/company/transfer');

  Future<TransferOffer> startOwnerRecovery(String newPhone) async =>
      TransferOffer.fromJson(asMap(await _c.post('/company/owner-recovery', body: {'newPhone': newPhone})));

  /// Accept returns a session as main owner; decline returns null.
  Future<AuthResult?> decideTransfer(
    String id, {
    required bool accept,
    required String deviceId,
    String? refreshToken,
  }) async {
    final d = await _c.post(
      '/me/transfers/$id/${accept ? 'accept' : 'decline'}',
      body: {'deviceId': deviceId, 'refreshToken': ?refreshToken},
    );
    return d is Map ? AuthResult.fromJson(asMap(d)) : null;
  }

  /// Returns the test code when the email provider is a mock.
  Future<String?> requestEmailRecovery(String email) async =>
      asStringOrNull(asMap(await _c.post('/me/recovery/email', body: {'email': email}))['devCode']);

  Future<AuthResult> verifyEmailRecovery({
    required String email,
    required String code,
    required String deviceId,
    String? refreshToken,
  }) async => AuthResult.fromJson(
    asMap(
      await _c.post(
        '/me/recovery/email/verify',
        body: {'email': email, 'code': code, 'deviceId': deviceId, 'refreshToken': ?refreshToken},
      ),
    ),
  );

  Future<RecoveryHold> submitRecovery({
    required String oldPhone,
    required String businessName,
    String? gstin,
    String? paymentTxnId,
    String? selfieVideoBase64,
  }) async => RecoveryHold.fromJson(
    asMap(
      await _c.post(
        '/me/recovery-requests',
        body: {
          'oldPhone': oldPhone,
          'businessName': businessName,
          'gstin': ?gstin,
          'paymentTxnId': ?paymentTxnId,
          'selfieVideoBase64': ?selfieVideoBase64,
        },
      ),
    ),
  );

  Future<List<RecoveryHold>> myRecoveries() async =>
      asList(await _c.get('/me/recovery-requests'), RecoveryHold.fromJson);

  Future<void> stopRecovery(String id) async => _c.post('/me/recovery-holds/$id/stop');

  Future<void> deleteAccount(String code) async => _c.post('/me/delete', body: {'code': code});

  Future<List<PastPayslipGroup>> pastPayslips() async =>
      asList(await _c.get('/me/past-payslips'), PastPayslipGroup.fromJson);

  // ---------------------------------------------------------------- Phase 4

  Future<void> pin(String membershipId, {required bool pinned}) async =>
      _c.patch('/me/accounts/$membershipId', body: {'pinned': pinned});

  Future<BillingGroup> billingGroup() async => BillingGroup.fromJson(asMap(await _c.get('/billing/group')));

  Future<BillingGroup> addToBill(String companyId) async =>
      BillingGroup.fromJson(asMap(await _c.post('/billing/group/members', body: {'companyId': companyId})));

  Future<BillingGroup> removeFromBill(String companyId) async =>
      BillingGroup.fromJson(asMap(await _c.delete('/billing/group/members/$companyId')));
}
