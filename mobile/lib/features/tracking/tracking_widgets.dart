import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/providers.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'tracking_controller.dart';

String _km(int m) => (m / 1000).toStringAsFixed(m < 10000 ? 1 : 0);

/// Staff home: the owner asked to share location (agree), or it's being shared right now.
class TrackingHomeCard extends ConsumerWidget {
  const TrackingHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final t = ref.watch(trackingControllerProvider);
    final me = t.me;
    if (me == null) return const SizedBox.shrink();
    if (me.needsConsent) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Card(
          key: const Key('trackAskCard'),
          color: AppColors.amberLight,
          child: ListTile(
            leading: const Icon(Icons.share_location_rounded, color: AppColors.amberDark),
            title: Text(s.trackAskTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(s.trackAskHint(me.businessName)),
            trailing: FilledButton(
              key: const Key('trackRead'),
              onPressed: () => openTrackingConsent(context),
              child: Text(s.trackRead),
            ),
          ),
        ),
      );
    }
    if (!t.running) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        key: const Key('trackSharing'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            const Icon(Icons.my_location_rounded, color: AppColors.mintDark, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.trackSharingNow, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (me.distanceM > 0)
              Text(
                s.trackKmToday(_km(me.distanceM)),
                style: const TextStyle(color: AppColors.mintDark, fontWeight: FontWeight.w800),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> openTrackingConsent(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute<void>(builder: (_) => const TrackingConsentScreen()));

/// The one-time consent, in plain words. This screen is also the "prominent disclosure" Google Play asks for.
class TrackingConsentScreen extends ConsumerStatefulWidget {
  const TrackingConsentScreen({super.key});

  @override
  ConsumerState<TrackingConsentScreen> createState() => _TrackingConsentScreenState();
}

class _TrackingConsentScreenState extends ConsumerState<TrackingConsentScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final me = ref.watch(trackingControllerProvider).me ?? const MyTracking();
    final lines = s.isHindi ? me.consentHi : me.consentEn;
    return Scaffold(
      appBar: AppBar(title: Text(s.trackConsentTitle)),
      body: ListView(
        key: const Key('trackConsent'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const Icon(Icons.share_location_rounded, size: 56, color: AppColors.mintDark),
          const SizedBox(height: 10),
          Text(s.trackAskTitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(s.trackAskHint(me.businessName), style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_outline_rounded, color: AppColors.mintDark, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l, style: const TextStyle(fontSize: 15.5, height: 1.35))),
                ],
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('trackAgree'),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final ok = await runGuarded(
                      context,
                      () => ref
                          .read(trackingControllerProvider.notifier)
                          .consent(title: s.trackNotifTitle, text: s.trackNotifText),
                    );
                    if (!context.mounted) return;
                    setState(() => _busy = false);
                    if (ok) {
                      showSnack(context, s.trackAgreed);
                      Navigator.pop(context);
                    }
                  },
            child: Text(s.trackAgree),
          ),
          TextButton(
            key: const Key('trackNotNow'),
            onPressed: () => Navigator.pop(context),
            child: Text(s.trackNotNow),
          ),
        ],
      ),
    );
  }
}

/// Staff profile: location sharing is on (stop it), or the owner asked (read and agree).
class TrackingProfileTile extends ConsumerWidget {
  const TrackingProfileTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final me = ref.watch(trackingControllerProvider).me;
    if (me == null || !me.enabled) return const SizedBox.shrink();
    return Card(
      key: const Key('trackProfile'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ListTile(
        leading: const Icon(Icons.share_location_rounded, color: AppColors.mintDark),
        title: Text(s.trackConsentTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(me.consented ? s.trackProfileOn : s.trackProfileAsk),
        trailing: me.consented
            ? TextButton(
                key: const Key('trackStop'),
                onPressed: () async {
                  final yes = await confirmDialog(
                    context,
                    title: s.trackStop,
                    message: s.trackStopConfirm,
                    destructive: true,
                  );
                  if (!yes || !context.mounted) return;
                  final ok = await runGuarded(context, () => ref.read(trackingControllerProvider.notifier).withdraw());
                  if (ok && context.mounted) showSnack(context, s.trackStopped);
                },
                child: Text(s.trackStop),
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: me.consented ? null : () => openTrackingConsent(context),
      ),
    );
  }
}

/// Owner/manager, staff profile: make this person field staff (they share location during the shift once they agree).
class FieldStaffSwitch extends ConsumerStatefulWidget {
  const FieldStaffSwitch({super.key, required this.employee, required this.onChanged});
  final Employee employee;
  final VoidCallback onChanged;

  @override
  ConsumerState<FieldStaffSwitch> createState() => _FieldStaffSwitchState();
}

class _FieldStaffSwitchState extends ConsumerState<FieldStaffSwitch> {
  late bool _on = widget.employee.trackingEnabled;
  late bool _agreed = widget.employee.trackingConsented;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final status = !_on ? s.fieldStaffOff : (_agreed ? s.fieldStaffOn : s.fieldStaffWaiting(widget.employee.name));
    return Card(
      key: const Key('fieldStaffCard'),
      child: SwitchListTile(
        key: const Key('fieldStaffSwitch'),
        secondary: const Icon(Icons.share_location_rounded, color: AppColors.mintDark),
        title: Text(s.fieldStaff, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(status, style: TextStyle(color: _on && !_agreed ? AppColors.amberDark : AppColors.muted)),
        value: _on,
        onChanged: _busy
            ? null
            : (v) async {
                setState(() => _busy = true);
                ({bool enabled, bool consented})? r;
                await runGuarded(
                  context,
                  () async => r = await ref.read(trackingApiProvider).setFor(widget.employee.id, v),
                );
                if (!mounted) return;
                setState(() {
                  _busy = false;
                  if (r != null) {
                    _on = r!.enabled;
                    _agreed = r!.consented;
                  }
                });
                if (r != null) widget.onChanged();
              },
      ),
    );
  }
}
