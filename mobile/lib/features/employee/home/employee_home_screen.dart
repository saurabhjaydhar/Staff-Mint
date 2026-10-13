import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../tracking/tracking_controller.dart';
import '../../tracking/tracking_widgets.dart';
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
import '../../../core/widgets/shift_chip.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/success_screen.dart';
import '../../accounts/accounts_screen.dart' show AccountAlerts, BusinessSwitchChip;
import '../../auth/auth_controller.dart';
import '../employee_providers.dart';
import '../punch/punch_capture.dart';
import '../punch/punch_providers.dart';
import '../punch/punch_service.dart';
import '../punch/punch_state.dart';
import 'check_in_button.dart';
import 'swap_widgets.dart';
import '../verify/verify_screen.dart';

/// Employee home: the shift in words ("Started 12 minutes ago", never "848
/// min late"), where they are and why it matters, one big button that says
/// what it does, a clear path when they're away, and the month in words.
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetch();
      _track();
    });
  }

  /// Field staff: start or stop sharing location (after check-in / check-out, and when the app opens).
  Future<void> _track({bool checkedOut = false}) async {
    if (!mounted) return;
    final s = context.s;
    final c = ref.read(trackingControllerProvider.notifier);
    if (checkedOut) await c.checkedOut();
    await c.refresh(title: s.trackNotifTitle, text: s.trackNotifText);
  }

  Future<void> _prefetch() async {
    // Owner-marked staff never check in, so don't ask for their location.
    if (!mounted || _locating || ref.read(authControllerProvider).ownerMarksAttendance) return;
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
          unawaited(_track(checkedOut: type == 'out'));
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
                response.punch.insideGeofence == false || loc.isMocked
                    ? s.pendingApprovalNote
                    : response.punch.faceFlagged
                    ? s.facePendingNote
                    : s.lockPendingNote,
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
      ?(session.activeMembership?.companyName ?? session.company?.name),
      Dates.weekdayShort(DateTime.now(), s.languageCode),
    ].join(' · ');
    final firstName = (session.employee?.name ?? session.user?.name ?? '').split(' ').first;
    final away = _awayMeters(info);
    final selfie = session.company?.settings.selfieRequired ?? true;
    // The owner or a manager marks attendance: show the day, no check-in button.
    final ownerMarks = info?.ownerMarks ?? session.ownerMarksAttendance;

    return Scaffold(
      body: SafeArea(
        child: RefreshableList(
          onRefresh: () async {
            ref.invalidate(employeeTodayProvider);
            ref.invalidate(myRosterProvider);
            ref.invalidate(mySwapsProvider);
            ref.invalidate(myVerificationProvider);
            _prefetch().ignore();
            await ref.read(punchSyncProvider.notifier).syncNow();
            await ref.read(employeeTodayProvider.future);
          },
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ScreenHeader(subtitle: subtitle, title: s.namaste(firstName)),
            const BusinessSwitchChip(),
            const AccountAlerts(),
            if (!ownerMarks &&
                session.company?.settings.faceMatchPolicy == 'review' &&
                session.employee?.faceStatus == 'none')
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
            if (_shiftCard(s, record, shift, ownerMarks: ownerMarks) case final card?)
              Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: card),
            if (!ownerMarks && buttonState != PunchButtonState.completed)
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: _locationCard(s, info)),
            if (ownerMarks)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _InfoCard(
                  key: const Key('markedByOwner'),
                  icon: Icons.how_to_reg_rounded,
                  color: AppColors.mintDark,
                  title: s.todayIs(s.statusLabel(info?.displayStatus)),
                  body: s.markedByOwnerBody,
                ),
              ),
            if (!ownerMarks) const SizedBox(height: 36),
            if (!ownerMarks)
              Center(
                child: today.isLoading && !today.hasValue
                    ? const SkeletonBox(width: 220, height: 220, radius: 110)
                    : CheckInButton(
                        state: buttonState,
                        busy: _busy,
                        busyLabel: _busyLabel,
                        checkInHint: selfie ? s.checkInHintSelfie : s.checkInHint,
                        onPressed: () => _punch(buttonState, info),
                      ),
              ),
            if (!ownerMarks) const SizedBox(height: 34),
            if (!ownerMarks)
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
            if (!ownerMarks && away != null && buttonState == PunchButtonState.checkIn)
              Card(
                key: const Key('workingOutside'),
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: ListTile(
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: Text(s.workingOutside),
                  trailing: Text(
                    '${s.askOwnerAllow} ›',
                    style: const TextStyle(color: AppColors.mintDark, fontWeight: FontWeight.w800),
                  ),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(s.workingOutside),
                      content: Text(s.workingOutsideBody),
                      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(s.ok))],
                    ),
                  ),
                ),
              ),
            const TrackingHomeCard(),
            const _VerifyCard(),
            const _MyWeek(),
            const _Swaps(),
            const Padding(padding: EdgeInsets.fromLTRB(16, 18, 16, 0), child: _MonthSummary()),
          ],
        ),
      ),
    );
  }

  /// Metres from the shop when outside its area; null when inside or unknown.
  num? _awayMeters(TodayInfo? info) {
    final g = info?.branch?.location;
    final loc = _loc;
    if (g == null || loc == null || (info?.fieldStaff ?? false)) return null;
    final d = distanceMeters(loc.lat, loc.lng, g.lat, g.lng);
    return d <= (info?.branch?.radiusM ?? 100) ? null : d;
  }

  /// Where they are, and why it matters: "You're at the shop ✓ · We check
  /// this so attendance is fair", or "You're 400 m from the shop" with a fix.
  Widget _locationCard(S s, TodayInfo? info) {
    if (info?.fieldStaff ?? false) {
      return _InfoCard(
        key: const Key('fieldStaffCard'),
        icon: Icons.share_location_rounded,
        color: AppColors.mintDark,
        title: s.fieldCheckInAnywhere,
        body: s.fieldCheckInHint,
      );
    }
    final loc = _loc;
    final g = info?.branch?.location;
    final askOwner = ref.read(authControllerProvider).company?.settings.outsideGeofencePolicy == 'request_approval';
    if (_locFailed && loc == null) {
      return _InfoCard(
        key: const Key('locationCard'),
        icon: Icons.location_off_rounded,
        color: AppColors.red,
        title: s.locationOffTitle,
        body: s.locationOffBody,
        actions: [
          TextButton(onPressed: _prefetch, child: Text(s.tryAgain)),
          TextButton(onPressed: _locationHelp, child: Text(s.locationProblem)),
        ],
      );
    }
    if (loc == null || (_locating && g == null)) {
      return _InfoCard(
        key: const Key('locationCard'),
        icon: Icons.my_location_rounded,
        color: AppColors.muted,
        title: s.findingYou,
        body: s.locationWhy,
      );
    }
    final away = _awayMeters(info);
    if (away == null) {
      return _InfoCard(
        key: const Key('locationCard'),
        icon: Icons.location_on_rounded,
        color: AppColors.mint,
        title: '${s.atShopTitle} ✓',
        body: s.locationWhy,
        onTap: _prefetch,
      );
    }
    return _InfoCard(
      key: const Key('locationCard'),
      icon: Icons.wrong_location_rounded,
      color: AppColors.red,
      title: s.awayTitle(away),
      body: askOwner ? s.awayBodyAsk : s.awayBody,
      actions: [
        TextButton(key: const Key('locationRetry'), onPressed: _prefetch, child: Text(s.tryAgain)),
        TextButton(onPressed: _locationHelp, child: Text(s.locationProblem)),
      ],
    );
  }

  void _locationHelp() {
    final s = context.s;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.locationProblem),
        content: Text(s.locationProblemBody),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(s.ok))],
      ),
    );
  }

  /// "Your shift: 9:00 AM – 9:00 PM · Started 12 minutes ago" (only for the
  /// first 3 hours; after that just the shift), or "In at 9:02 · 7 min late".
  Widget? _shiftCard(S s, Attendance? record, Shift? shift, {bool ownerMarks = false}) {
    if (shift == null) return null;
    final lang = s.languageCode;
    final title = s.yourShift(Dates.hhmmToDisplay(shift.start, lang), Dates.hhmmToDisplay(shift.end, lang));
    final firstIn = record?.firstIn;
    String? body;
    var color = AppColors.mintDark;
    if (ownerMarks) {
      // No "Started 40 minutes ago" nudge: they don't check in.
    } else if (firstIn != null) {
      final late = record!.lateMinutes;
      body = s.inAtLate(Dates.time(firstIn.clientTime, lang), late);
      if (late > 0) color = AppColors.amberDark;
    } else {
      final start = Dates.hhmmToMinutes(shift.start);
      if (start != null) {
        final now = DateTime.now();
        final since = now.hour * 60 + now.minute - start;
        if (since < 0) {
          body = s.shiftStartsAt(Dates.hhmmToDisplay(shift.start, lang));
        } else if (since < 180) {
          body = s.startedAgo(since);
          final grace = shift.graceMinutes ?? ref.read(authControllerProvider).company?.settings.graceMinutes ?? 15;
          if (since > grace) color = AppColors.amberDark;
        }
      }
    }
    return _InfoCard(key: const Key('shiftCard'), icon: Icons.schedule_rounded, color: color, title: title, body: body);
  }
}

/// A full-width card: icon, a plain sentence, and a reason or next step.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.body,
    this.actions = const [],
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String? body;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppColors.line, width: 1.5),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, actions.isEmpty ? 10 : 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      if (body != null)
                        Text(body!, style: const TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.3)),
                    ],
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
        ),
      ),
    ),
  );
}

/// "October so far · ✓ 8 days present · ⏰ 1 late · ✕ 1 absent ·
/// Earned till today: ₹3,387" — counts in words instead of codes.
/// The owner asked for a documents check and there's something to do.
class _VerifyCard extends ConsumerWidget {
  const _VerifyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final v = ref.watch(myVerificationProvider).value;
    if (v == null || !v.todo) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Card(
        key: const Key('verifyHomeCard'),
        color: AppColors.amberLight,
        child: ListTile(
          leading: const Icon(Icons.verified_user_rounded, color: AppColors.amberDark),
          title: Text(s.verifyCardTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(s.verifyCardHint(v.businessName)),
          trailing: FilledButton(
            key: const Key('verifyHomeStart'),
            onPressed: () => context.push(Routes.employeeVerify),
            child: Text(s.verifyStart),
          ),
        ),
      ),
    );
  }
}

class _Swaps extends ConsumerWidget {
  const _Swaps();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(myRosterProvider(Dates.toApiDate(DateTime.now()))).value;
    if (week == null || !week.swapsAllowed) return const SizedBox.shrink();
    return MySwaps(week: week);
  }
}

/// The week as the owner sent it: one line per day, today marked, changed days tagged.
/// Shown only when the business uses the roster.
class _MyWeek extends ConsumerWidget {
  const _MyWeek();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final todayStr = Dates.toApiDate(DateTime.now());
    final week = ref.watch(myRosterProvider(todayStr)).value;
    if (week == null || !week.rostered) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Material(
        key: const Key('myWeek'),
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.line, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.myWeek, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 6),
              for (final d in week.days)
                Container(
                  key: Key('myWeek_${d.date}'),
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: d.date == todayStr ? AppColors.mintLight : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          d.date == todayStr ? s.today : s.weekdayShort(Dates.parseDate(d.date).weekday % 7),
                          style: TextStyle(fontWeight: d.date == todayStr ? FontWeight.w800 : FontWeight.w600),
                        ),
                      ),
                      Flexible(
                        child: d.leave != null
                            ? Text(
                                s.onLeaveTag,
                                style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700),
                              )
                            : d.holiday != null
                            ? Text(
                                d.holiday!,
                                style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700),
                              )
                            : ShiftChip(shifts: week.shifts, shiftId: d.shiftId, off: d.kind == 'off'),
                      ),
                      if (d.changed) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.orangeLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            s.changedTag,
                            style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (week.swapsAllowed)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('mySwapButton'),
                    onPressed: () => showSwapSheet(context, week),
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: Text(s.swapADay),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthSummary extends ConsumerWidget {
  const _MonthSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final month = Dates.firstOfMonth(DateTime.now());
    final grid = ref.watch(myMonthProvider(Dates.toApiMonth(month))).value;
    final estimate = ref.watch(mySalaryProvider).value?.estimate;
    final row = grid?.rows.firstOrNull;
    if (grid == null || row == null) return const SizedBox.shrink();
    final t = row.totals;
    final present = (t['present'] ?? 0) + (t['halfDay'] ?? 0) * 0.5;
    final monthName = Dates.monthTitle(month, s.languageCode).split(' ').first;
    Widget count(String status, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(StatusStyle.of(status).icon, size: 16, color: StatusStyle.of(status).fg),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
    return Material(
      key: const Key('monthSummary'),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go(Routes.employeeAttendance),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.monthSoFar(monthName),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                  Text(
                    '${s.seeAll} ›',
                    style: const TextStyle(color: AppColors.mintDark, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  count('present', s.daysPresentN(present)),
                  if ((t['late'] ?? 0) > 0) count('late', s.chipLateN((t['late'] ?? 0).round())),
                  if ((t['absent'] ?? 0) > 0) count('absent', s.chipAbsentN((t['absent'] ?? 0).round())),
                  if ((t['leave'] ?? 0) > 0) count('leave', s.chipLeaveN((t['leave'] ?? 0).round())),
                ],
              ),
              if (estimate != null) ...[
                const SizedBox(height: 6),
                Text(
                  s.earnedTillToday(Money.format(estimate.netPaise)),
                  key: const Key('monthEarned'),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.mint),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
