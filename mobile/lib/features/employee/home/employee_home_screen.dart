import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/storage/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/geo.dart';
import '../../../core/utils/location.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/bilingual.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/month_dots.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/success_screen.dart';
import '../../auth/auth_controller.dart';
import '../employee_providers.dart';
import '../punch/punch_capture.dart';
import '../punch/punch_providers.dart';
import '../punch/punch_service.dart';
import '../punch/punch_state.dart';
import 'check_in_button.dart';

/// Employee home: GPS is fetched as soon as the screen opens, two chips say
/// "at shop?" and "on time?", one big button checks in, and a full-screen
/// success confirms it (with an offline variant).
class EmployeeHomeScreen extends ConsumerStatefulWidget {
  const EmployeeHomeScreen({super.key});

  @override
  ConsumerState<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends ConsumerState<EmployeeHomeScreen> {
  /// A prefetched fix younger than this is reused for the punch.
  static const _freshFor = Duration(seconds: 90);

  bool _busy = false;
  String? _busyLabel;
  CapturedLocation? _loc;
  DateTime? _locAt;
  bool _locating = false;
  bool _locFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetch());
  }

  Future<void> _prefetch() async {
    if (!mounted || _locating) return;
    setState(() {
      _locating = true;
      _locFailed = false;
    });
    try {
      final l = await ref.read(punchCaptureProvider).location();
      if (!mounted) return;
      setState(() {
        _loc = l;
        _locAt = DateTime.now();
      });
    } catch (_) {
      if (mounted) setState(() => _locFailed = true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _setBusy(String? label) => setState(() {
    _busy = label != null;
    _busyLabel = label;
  });

  Future<CapturedLocation> _location() {
    final at = _locAt;
    if (_loc != null && at != null && DateTime.now().difference(at) < _freshFor) return Future.value(_loc);
    return ref.read(punchCaptureProvider).location();
  }

  Future<void> _punch(PunchButtonState buttonState, TodayInfo? info) async {
    final s = context.s;
    final type = punchTypeFor(buttonState);
    final tappedAt = DateTime.now();
    final capture = ref.read(punchCaptureProvider);
    final settings = ref.read(authControllerProvider).company?.settings;
    final selfieRequired = settings?.selfieRequired ?? true;
    final lockPolicy = settings?.phoneLockPolicy ?? 'recommended';
    final liveSelfie =
        settings?.faceMatchPolicy == 'review' && ref.read(authControllerProvider).employee?.faceStatus == 'approved';

    _setBusy(s.gettingLocation);
    // GPS (usually ready already) runs while the camera is open.
    final locationFuture = _location().then<Object>((l) => l, onError: (Object e) => e);
    try {
      String? lockCheck;
      if (lockPolicy != 'off') {
        _setBusy(s.unlockingPhone);
        lockCheck = await _unlock(capture, required: lockPolicy == 'required');
        if (lockCheck == null || !mounted) return;
      }
      String? selfie;
      if (selfieRequired) {
        _setBusy(s.takingSelfie);
        selfie = await capture.selfie(context, live: liveSelfie);
        if (selfie == null) {
          if (mounted) showSnack(context, s.selfieNeeded, error: true);
          return;
        }
        if (mounted) _setBusy(s.gettingLocation);
      }
      final loc = await locationFuture;
      if (loc is! CapturedLocation) throw loc;
      if (!mounted) return;
      _setBusy(s.submitting);

      final request = PunchRequest(
        type: type,
        clientTime: tappedAt,
        lat: loc.lat,
        lng: loc.lng,
        accuracyM: loc.accuracyM,
        mockLocation: loc.isMocked,
        deviceId: await ref.read(deviceIdServiceProvider).getDeviceId(),
        selfieBase64: selfie,
        lockCheck: lockCheck,
      );
      final outcome = await ref.read(punchServiceProvider).submit(request);
      if (!mounted) return;
      _setBusy(null);
      final rows = <(String, String)>[
        (s.timeLabel, Dates.time(tappedAt, s.languageCode)),
        (s.selfieLabel, selfie == null ? s.notNeeded : s.selfieSaved),
        if (lockCheck != null) (s.phoneLockLabel, s.lockCheckLabel(lockCheck)),
        if (_placeText(info, loc) case final place?) (s.locationLabel, place),
        if (info?.shift case final shift?)
          (
            s.shift,
            '${Dates.hhmmToDisplay(shift.start, s.languageCode)} – ${Dates.hhmmToDisplay(shift.end, s.languageCode)}',
          ),
      ];
      switch (outcome) {
        case PunchSucceeded(:final response):
          ref.invalidate(employeeTodayProvider);
          ref.invalidate(myMonthProvider);
          final bi = type == 'in' ? s.checkedInBi : s.checkedOutBi;
          final late = response.record.lateMinutes;
          await showSuccessScreen(
            context,
            title: bi.text,
            subtitle: [
              ?bi.hint,
              Dates.time(tappedAt, s.languageCode),
              if (type == 'in') late > 0 ? s.lateBy(late) : s.onTime.text,
            ].join(' · '),
            rows: rows,
            note: [
              if (response.punch.isPendingApproval)
                response.punch.insideGeofence == false || loc.isMocked ? s.pendingApprovalNote : s.lockPendingNote,
              if (loc.isMocked) s.mockLocationWarning,
            ].join('\n').ifEmptyNull,
          );
        case PunchQueued():
          setState(() {});
          final bi = s.savedOfflineBi;
          await showSuccessScreen(
            context,
            title: bi.text,
            subtitle: [?bi.hint, s.willSync].join(' · '),
            rows: rows,
            offline: true,
          );
        case PunchFailed(:final error):
          if (error.isOutsideGeofence) {
            await _showGeofenceDialog(error);
          } else {
            showError(context, error);
          }
      }
    } on LocationException catch (e) {
      if (mounted) {
        showSnack(context, e.serviceDisabled ? s.locationServiceOff : s.locationPermissionDenied, error: true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) _setBusy(null);
    }
  }

  /// Phone screen lock. A failure offers "try again" or "check in without
  /// it" — it never blocks the check-in. Null when the user backs out.
  Future<String?> _unlock(PunchCapture capture, {required bool required}) async {
    final s = context.s;
    while (true) {
      final r = await capture.unlock(s.unlockReason);
      if (r != LockCheck.failed || !mounted) return r;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.lock_outline_rounded, color: AppColors.amber, size: 44),
          title: Text(s.unlockFailedTitle),
          content: Text(s.unlockFailedBody(required)),
          actions: [
            TextButton(
              key: const Key('lockContinueWithout'),
              onPressed: () => Navigator.pop(ctx, 'continue'),
              child: Text(s.continueWithoutLock),
            ),
            FilledButton(
              key: const Key('lockRetry'),
              onPressed: () => Navigator.pop(ctx, 'retry'),
              child: Text(s.retry),
            ),
          ],
        ),
      );
      if (choice == 'continue') return LockCheck.failed;
      if (choice != 'retry') return null;
    }
  }

  /// "Sharma Medical · 12 m" when the branch location is known.
  String? _placeText(TodayInfo? info, CapturedLocation loc) {
    final b = info?.branch;
    final g = b?.location;
    if (b == null) return null;
    if (g == null) return b.name;
    final d = distanceMeters(loc.lat, loc.lng, g.lat, g.lng);
    return '${b.name} · ${context.s.metersShort(d)}';
  }

  Future<void> _showGeofenceDialog(ApiException error) {
    final s = context.s;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.wrong_location_rounded, color: AppColors.red, size: 48),
        title: Text(s.outsideGeofence),
        content: Text([if (error.message.isNotEmpty) error.message, s.outsideGeofenceHelp].join('\n\n')),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(s.ok))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    final today = ref.watch(employeeTodayProvider);
    final sync = ref.watch(punchSyncProvider);
    final pending = ref.read(punchQueueProvider).pending;
    final info = today.value?.info;
    final record = info?.record;
    final buttonState = deriveButtonState(record: record, pending: pending, today: Dates.toApiDate(DateTime.now()));
    final shift = info?.shift;
    final firstIn = record?.firstIn;
    final lastOut = record?.lastOut;

    final statusText = switch (buttonState) {
      PunchButtonState.checkIn => s.notCheckedIn,
      PunchButtonState.checkOut => s.workingNow,
      PunchButtonState.completed => s.dayComplete,
    };
    final subtitle = [
      Dates.weekdayShort(DateTime.now(), s.languageCode),
      if (shift != null)
        s.shiftShort(Dates.hhmmToDisplay(shift.start, s.languageCode), Dates.hhmmToDisplay(shift.end, s.languageCode)),
    ].join(' · ');

    return Scaffold(
      body: SafeArea(
        child: RefreshableList(
          onRefresh: () async {
            ref.invalidate(employeeTodayProvider);
            _prefetch().ignore();
            await ref.read(punchSyncProvider.notifier).syncNow();
            await ref.read(employeeTodayProvider.future);
          },
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ScreenHeader(subtitle: subtitle, title: s.hello(session.employee?.name ?? session.user?.name ?? '')),
            if (session.company?.settings.faceMatchPolicy == 'review' && session.employee?.faceStatus == 'none')
              Card(
                key: const Key('faceSetupBanner'),
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                color: AppColors.mintFaint,
                child: ListTile(
                  leading: const Icon(Icons.face_retouching_natural_rounded, color: AppColors.mint),
                  title: Text(s.faceSetupBanner, style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(Routes.employeeFace),
                ),
              ),
            if (sync.pending > 0)
              Container(
                key: const Key('pendingSyncBanner'),
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: AppColors.amberLight, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_upload_outlined, color: AppColors.amberDark),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.pendingSync(sync.pending))),
                    sync.syncing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton(
                            onPressed: () => ref.read(punchSyncProvider.notifier).syncNow(),
                            child: Text(s.syncNow),
                          ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _locationChip(s, info)),
                    if (_timeChip(s, record, shift) case final chip?) ...[
                      const SizedBox(width: 8),
                      Expanded(child: chip),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            Center(
              child: today.isLoading && !today.hasValue
                  ? const SkeletonBox(width: 220, height: 220, radius: 110)
                  : CheckInButton(
                      state: buttonState,
                      busy: _busy,
                      busyLabel: _busyLabel,
                      onPressed: () => _punch(buttonState, info),
                    ),
            ),
            const SizedBox(height: 34),
            Text(
              [
                statusText,
                if (firstIn != null) s.checkedInAt(Dates.time(firstIn.clientTime, s.languageCode)),
                if (lastOut != null) s.checkedOutAt(Dates.time(lastOut.clientTime, s.languageCode)),
              ].join(' · '),
              key: const Key('todayStatusText'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
            ),
            if (today.value?.fromCache ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.muted),
                    const SizedBox(width: 6),
                    Text(s.offlineNote, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
                  ],
                ),
              ),
            if (today.hasError && !today.hasValue)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  errorMessage(context, today.error!),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
            const Padding(padding: EdgeInsets.fromLTRB(16, 18, 16, 0), child: _MonthStrip()),
          ],
        ),
      ),
    );
  }

  Widget _locationChip(S s, TodayInfo? info) {
    final g = info?.branch?.location;
    final loc = _loc;
    if (_locating && loc == null) return _StatusTile(icon: Icons.my_location_rounded, label: s.locating);
    if (_locFailed && loc == null) {
      return _StatusTile(icon: Icons.location_off_rounded, label: s.gpsOff, color: AppColors.red, onTap: _prefetch);
    }
    if (loc == null) return _StatusTile(icon: Icons.my_location_rounded, label: s.locating);
    if (g == null) {
      return _StatusTile(
        icon: Icons.location_on_rounded,
        label: s.gpsReady,
        detail: s.accuracy(loc.accuracyM),
        color: AppColors.mint,
        onTap: _prefetch,
      );
    }
    final d = distanceMeters(loc.lat, loc.lng, g.lat, g.lng);
    final inside = d <= (info?.branch?.radiusM ?? 100);
    return _StatusTile(
      key: const Key('locationChip'),
      icon: inside ? Icons.location_on_rounded : Icons.wrong_location_rounded,
      label: inside ? s.atShop : s.awayFromShop,
      detail: s.metersShort(d),
      color: inside ? AppColors.mint : AppColors.red,
      onTap: _prefetch,
    );
  }

  Widget? _timeChip(S s, Attendance? record, Shift? shift) {
    final firstIn = record?.firstIn;
    if (firstIn != null) {
      final late = record!.lateMinutes;
      return _StatusTile(
        icon: Icons.schedule_rounded,
        label: late > 0 ? s.lateToday : s.onTime,
        detail: late > 0 ? s.minutesShort(late) : Dates.clock(firstIn.clientTime),
        color: late > 0 ? AppColors.amberDark : AppColors.mint,
      );
    }
    final start = shift == null ? null : Dates.hhmmToMinutes(shift.start);
    if (shift == null || start == null) return null;
    final grace = shift.graceMinutes ?? ref.read(authControllerProvider).company?.settings.graceMinutes ?? 15;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final late = nowMin > start + grace;
    return _StatusTile(
      icon: Icons.schedule_rounded,
      label: late ? s.runningLate : s.onTime,
      detail: late ? s.minutesShort(nowMin - start) : Dates.hhmmToDisplay(shift.start, s.languageCode),
      color: late ? AppColors.amberDark : AppColors.mint,
    );
  }
}

/// "📍 दुकान पर / At shop · 12 m" style chip.
class _StatusTile extends StatelessWidget {
  const _StatusTile({super.key, required this.icon, required this.label, this.detail, this.color, this.onTap});
  final IconData icon;
  final Bi label;
  final String? detail;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.muted;
    final sub = [?label.hint, ?detail].join(' · ');
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: c, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "अक्टूबर · 7 दिन हाज़िर · ₹3,613 अब तक" with this month's day dots.
class _MonthStrip extends ConsumerWidget {
  const _MonthStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final month = Dates.firstOfMonth(DateTime.now());
    final grid = ref.watch(myMonthProvider(Dates.toApiMonth(month))).value;
    final estimate = ref.watch(mySalaryProvider).value?.estimate;
    final days = grid?.rows.firstOrNull?.days ?? const <String, String>{};
    if (grid == null) return const SizedBox.shrink();
    final present = days.values.where((d) => d == 'present' || d == 'late' || d == 'checked_in').length;
    final monthName = Dates.monthTitle(month, s.languageCode).split(' ').first;
    return MonthDots(
      month: month,
      days: days,
      title: s.monthDaysPresent(monthName, present),
      trailing: estimate == null ? null : s.earnedSoFar(Money.format(estimate.netPaise)),
    );
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
