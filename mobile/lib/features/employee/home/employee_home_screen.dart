import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/storage/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/location.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_controller.dart';
import '../punch/punch_capture.dart';
import '../punch/punch_providers.dart';
import '../punch/punch_service.dart';
import '../punch/punch_state.dart';
import 'check_in_button.dart';

/// Employee home: today's status, shift time and one big button.
/// Tap → selfie (camera: shutter + confirm) → saved. ≤ 3 taps.
class EmployeeHomeScreen extends ConsumerStatefulWidget {
  const EmployeeHomeScreen({super.key});

  @override
  ConsumerState<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends ConsumerState<EmployeeHomeScreen> {
  bool _busy = false;
  String? _busyLabel;

  void _setBusy(String? label) => setState(() {
    _busy = label != null;
    _busyLabel = label;
  });

  Future<void> _punch(PunchButtonState buttonState) async {
    final s = context.s;
    final type = punchTypeFor(buttonState);
    final tappedAt = DateTime.now();
    final capture = ref.read(punchCaptureProvider);
    final selfieRequired = ref.read(authControllerProvider).company?.settings.selfieRequired ?? true;

    _setBusy(s.gettingLocation);
    // Start GPS immediately; it runs while the camera is open.
    final locationFuture = capture.location().then<Object>((l) => l, onError: (Object e) => e);
    try {
      String? selfie;
      if (selfieRequired) {
        _setBusy(s.takingSelfie);
        selfie = await capture.selfie();
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
      );
      final outcome = await ref.read(punchServiceProvider).submit(request);
      if (!mounted) return;
      switch (outcome) {
        case PunchSucceeded(:final response):
          final notes = [
            type == 'in' ? s.checkInDone : s.checkOutDone,
            if (response.punch.isPendingApproval) s.pendingApprovalNote,
            if (loc.isMocked) s.mockLocationWarning,
          ];
          showSnack(context, notes.join('\n'));
          ref.invalidate(employeeTodayProvider);
        case PunchQueued():
          showSnack(context, s.savedOffline);
          setState(() {});
        case PunchFailed(:final error):
          if (error.isOutsideGeofence) {
            _setBusy(null);
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

  Future<void> _showGeofenceDialog(ApiException error) {
    final s = context.s;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.wrong_location_rounded, color: AppColors.absent, size: 48),
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
    final todayKey = Dates.toApiDate(DateTime.now());
    final info = today.value?.info;
    final record = info?.record;
    final buttonState = deriveButtonState(record: record, pending: pending, today: todayKey);
    final shift = info?.shift;
    final firstIn = record?.firstIn;
    final lastOut = record?.lastOut;

    final statusText = switch (buttonState) {
      PunchButtonState.checkIn => s.notCheckedIn,
      PunchButtonState.checkOut => s.workingNow,
      PunchButtonState.completed => s.dayComplete,
    };

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.hello(session.user?.name ?? session.employee?.name ?? '')),
            if (session.company != null)
              Text(
                session.company!.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
          ],
        ),
        toolbarHeight: 72,
      ),
      body: RefreshableList(
        onRefresh: () async {
          ref.invalidate(employeeTodayProvider);
          await ref.read(punchSyncProvider.notifier).syncNow();
          await ref.read(employeeTodayProvider.future);
        },
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (sync.pending > 0)
            Container(
              key: const Key('pendingSyncBanner'),
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.cloud_upload_outlined, color: AppColors.late),
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
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(s.todayStatus, style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      Text(Dates.weekdayShort(DateTime.now(), s.languageCode)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    statusText,
                    key: const Key('todayStatusText'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.mintDark),
                  ),
                  if (shift != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 20, color: Colors.black54),
                        const SizedBox(width: 6),
                        Text(
                          s.shiftTime(
                            Dates.hhmmToDisplay(shift.start, s.languageCode),
                            Dates.hhmmToDisplay(shift.end, s.languageCode),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (firstIn != null) Text(s.checkedInAt(Dates.time(firstIn.clientTime, s.languageCode))),
                  if (lastOut != null) Text(s.checkedOutAt(Dates.time(lastOut.clientTime, s.languageCode))),
                  if ((record?.lateMinutes ?? 0) > 0)
                    Text(
                      s.lateBy(record!.lateMinutes),
                      style: const TextStyle(color: AppColors.late, fontWeight: FontWeight.w600),
                    ),
                  if (record?.status != null) ...[
                    const SizedBox(height: 8),
                    StatusChip(status: record!.status, dense: true),
                  ],
                  if (today.value?.fromCache ?? false) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 18, color: Colors.black45),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(s.networkError, style: const TextStyle(color: Colors.black54, fontSize: 14)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: today.isLoading && !today.hasValue
                ? const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
                : CheckInButton(
                    state: buttonState,
                    busy: _busy,
                    busyLabel: _busyLabel,
                    onPressed: () => _punch(buttonState),
                  ),
          ),
          if (info?.branch != null) ...[
            const SizedBox(height: 20),
            Center(
              child: Text(
                '📍 ${info!.branch!.name}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
            ),
          ],
          if (today.hasError && !today.hasValue)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                errorMessage(context, today.error!),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.absent),
              ),
            ),
        ],
      ),
    );
  }
}
