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
import 'session_state.dart';

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
      await refreshMe(needsCompanySetupHint: result.needsCompanySetup);
    } catch (_) {
      state = SessionState(
        status: SessionStatus.authenticated,
        user: result.user,
        needsCompanySetup: result.needsCompanySetup,
      );
    }
    unawaited(_syncLanguage());
    unawaited(_registerPush());
  }

  Future<void> refreshMe({bool? needsCompanySetupHint}) async {
    final (me, json) = await ref.read(meApiProvider).me();
    await ref.read(tokenStorageProvider).writeSessionCache(json);
    state = _fromMe(me, needsCompanySetupHint: needsCompanySetupHint);
  }

  Future<void> createCompany(CreateCompanyRequest req) async {
    final res = await ref.read(companyApiProvider).create(req);
    await ref.read(tokenStorageProvider).saveTokens(accessToken: res.accessToken, refreshToken: res.refreshToken);
    state = state.copyWith(
      company: res.company,
      user: state.user?.copyWith(companyId: res.company.id),
      needsCompanySetup: false,
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

  SessionState _fromMe(MeResponse me, {bool? needsCompanySetupHint}) {
    final needsSetup = !me.user.isEmployee && me.company == null;
    return SessionState(
      status: SessionStatus.authenticated,
      user: me.user,
      company: me.company,
      employee: me.employee,
      needsCompanySetup: me.company != null ? false : (needsCompanySetupHint ?? needsSetup),
    );
  }

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
