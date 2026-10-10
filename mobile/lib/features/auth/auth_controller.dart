import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/providers.dart';
import '../../core/api/services/auth_api.dart';
import '../../core/api/services/company_api.dart';
import '../../core/api/services/me_api.dart';
import '../../core/i18n/locale_provider.dart';
import '../../core/push/push_service.dart';
import '../../core/storage/providers.dart';
import '../employee/punch/punch_providers.dart';
import 'session_state.dart';

/// Offline check-ins belong to the business they were made in, so they have
/// to reach the server before this phone moves to another account.
class PendingPunchesException implements Exception {
  const PendingPunchesException(this.count);
  final int count;
}

class AuthController extends Notifier<SessionState> {
  @override
  SessionState build() {
    Future.microtask(restore);
    return const SessionState.unknown();
  }

  /// Restores a saved session: cached `/me` first (offline-friendly), then a
  /// fresh `/me` from the server.
  Future<void> restore() async {
    final tokens = ref.read(tokenStorageProvider);
    if (!await tokens.hasSession()) {
      state = const SessionState.unauthenticated();
      return;
    }
    final cached = await tokens.readSessionCache();
    if (cached != null) {
      state = _fromMe(MeResponse.fromJson(cached));
    }
    try {
      await refreshMe();
      unawaited(_registerPush());
    } on ApiException catch (e) {
      if (e.isUnauthorized || e.isTokenExpired) {
        await tokens.clear();
        state = const SessionState.unauthenticated();
      } else if (cached == null) {
        state = const SessionState.unknown(restoreFailed: true);
      }
    } catch (_) {
      if (cached == null) state = const SessionState.unknown(restoreFailed: true);
    }
  }

  Future<OtpRequestResult> requestOtp(String phone, {String channel = 'sms'}) =>
      ref.read(authApiProvider).requestOtp(phone, channel: channel);

  Future<void> verifyOtp(String phone, String code) async {
    final deviceId = await ref.read(deviceIdServiceProvider).getDeviceId();
    final result = await ref
        .read(authApiProvider)
        .verifyOtp(phone: phone, code: code, deviceId: deviceId, deviceName: _deviceName());
    await ref.read(tokenStorageProvider).saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
    try {
      await refreshMe(needsCompanySetupHint: result.needsCompanySetup, needsAccountChoice: result.needsAccountChoice);
    } catch (_) {
      state = _fromAuth(result, needsAccountChoice: result.needsAccountChoice);
    }
    unawaited(_syncLanguage());
    unawaited(_registerPush());
  }

  Future<void> refreshMe({bool? needsCompanySetupHint, bool? needsAccountChoice}) async {
    final (me, json) = await ref.read(meApiProvider).me();
    await ref.read(tokenStorageProvider).writeSessionCache(json);
    state = _fromMe(
      me,
      needsCompanySetupHint: needsCompanySetupHint,
      needsAccountChoice: needsAccountChoice ?? (state.isAuthenticated && state.needsAccountChoice),
    );
  }

  /// The chooser after login: keep the account already open, or move to another.
  Future<void> chooseAccount(String membershipId) async {
    if (membershipId == state.activeMembershipId) {
      state = state.copyWith(needsAccountChoice: false);
      return;
    }
    await switchTo(membershipId);
  }

  /// Moves this phone into another of the person's businesses. Throws
  /// [PendingPunchesException] while offline check-ins are still unsent.
  Future<void> switchTo(String membershipId) async {
    await _sendQueuedPunches();
    final tokens = ref.read(tokenStorageProvider);
    final deviceId = await ref.read(deviceIdServiceProvider).getDeviceId();
    final res = await ref
        .read(authApiProvider)
        .switchAccount(membershipId: membershipId, deviceId: deviceId, refreshToken: await tokens.readRefreshToken());
    await tokens.saveTokens(accessToken: res.accessToken, refreshToken: res.refreshToken);
    _forgetBusinessData();
    try {
      await refreshMe(needsCompanySetupHint: res.needsCompanySetup, needsAccountChoice: false);
    } catch (_) {
      state = _fromAuth(res, needsAccountChoice: false);
    }
  }

  Future<void> _sendQueuedPunches() async {
    final int pending;
    try {
      pending = ref.read(punchQueueProvider).length;
    } catch (_) {
      return; // no offline queue on this platform
    }
    if (pending == 0) return;
    try {
      await ref.read(punchSyncProvider.notifier).syncNow();
    } catch (_) {
      /* counted below */
    }
    final left = ref.read(punchQueueProvider).length;
    if (left > 0) throw PendingPunchesException(left);
  }

  /// Everything cached on screens belongs to the old business: rebuilding the
  /// API client makes every data provider fetch again.
  void _forgetBusinessData() {
    ref.invalidate(apiClientProvider);
    try {
      ref.read(cacheBoxProvider).delete('today');
    } catch (_) {}
  }

  /// "Check again" for staff waiting to be added: new tokens (the server links
  /// the number if the owner has added it), then a fresh session. True when
  /// the number is now staff.
  Future<bool> recheckStaffLink() async {
    final tokens = ref.read(tokenStorageProvider);
    final refresh = await tokens.readRefreshToken();
    if (refresh == null) return false;
    final t = await ref.read(authApiProvider).refresh(refresh);
    await tokens.saveTokens(accessToken: t.accessToken, refreshToken: t.refreshToken);
    await refreshMe();
    final u = state.user;
    return u != null && u.companyId != null && (u.isEmployee || u.role == 'manager');
  }

  /// First business, or another one from any account (staff included). This
  /// phone moves into the new business.
  Future<void> createCompany(CreateCompanyRequest req) async {
    final tokens = ref.read(tokenStorageProvider);
    final hadBusiness = state.user?.companyId != null;
    final deviceId = await ref.read(deviceIdServiceProvider).getDeviceId();
    final res = await ref
        .read(companyApiProvider)
        .create(req.withSession(deviceId: deviceId, refreshToken: await tokens.readRefreshToken()));
    await tokens.saveTokens(accessToken: res.accessToken, refreshToken: res.refreshToken);
    if (hadBusiness) _forgetBusinessData();
    state = SessionState(
      status: SessionStatus.authenticated,
      user: state.user?.copyWith(companyId: res.company.id, role: 'owner'),
      company: res.company,
      memberships: res.memberships.isEmpty ? state.memberships : res.memberships,
      activeMembershipId: res.activeMembershipId,
    );
    try {
      await refreshMe(needsCompanySetupHint: false);
    } catch (_) {
      /* keep optimistic state */
    }
  }

  Future<void> giveConsent() async {
    final employee = await ref.read(meApiProvider).giveLocationConsent();
    state = state.copyWith(employee: employee);
    try {
      await refreshMe();
    } catch (_) {}
  }

  Future<void> logout() async {
    final tokens = ref.read(tokenStorageProvider);
    final refresh = await tokens.readRefreshToken();
    if (refresh != null) {
      try {
        await ref.read(authApiProvider).logout(refresh).timeout(const Duration(seconds: 5));
      } catch (_) {
        /* logging out locally is enough */
      }
    }
    await tokens.clear();
    state = const SessionState.unauthenticated();
  }

  /// Called by the HTTP layer when the refresh token is no longer valid.
  void onSessionExpired() {
    if (state.status != SessionStatus.unauthenticated) {
      state = const SessionState.unauthenticated();
    }
  }

  SessionState _fromMe(MeResponse me, {bool? needsCompanySetupHint, bool needsAccountChoice = false}) {
    final needsSetup = !me.user.isEmployee && me.company == null;
    return SessionState(
      status: SessionStatus.authenticated,
      user: me.user,
      company: me.company,
      employee: me.employee,
      needsCompanySetup: me.company != null ? false : (needsCompanySetupHint ?? needsSetup),
      memberships: me.memberships,
      activeMembershipId: me.activeMembershipId,
      needsAccountChoice: needsAccountChoice && me.memberships.length > 1,
    );
  }

  SessionState _fromAuth(AuthResult r, {bool needsAccountChoice = false}) => SessionState(
    status: SessionStatus.authenticated,
    user: r.user,
    needsCompanySetup: r.needsCompanySetup,
    memberships: r.memberships,
    activeMembershipId: r.activeMembershipId,
    needsAccountChoice: needsAccountChoice && r.memberships.length > 1,
  );

  Future<void> _syncLanguage() async {
    final lang = ref.read(localeProvider);
    final user = state.user;
    if (user == null || user.language == lang) return;
    try {
      await ref.read(meApiProvider).update(language: lang);
    } catch (_) {}
  }

  Future<void> _registerPush() async {
    try {
      await ref.read(pushServiceProvider).register(ref.read(meApiProvider));
    } catch (_) {
      /* push is optional */
    }
  }

  static String _deviceName() {
    try {
      return Platform.isIOS ? 'iOS' : 'Android';
    } catch (_) {
      return 'mobile';
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, SessionState>(AuthController.new);
