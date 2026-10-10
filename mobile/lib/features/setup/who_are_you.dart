import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/bilingual.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_controller.dart';

/// First question for a number StaffMint doesn't know: owner or staff?
/// Staff must not create a business by accident.
class WhoAreYouView extends ConsumerWidget {
  const WhoAreYouView({super.key, required this.onOwner, required this.onStaff});
  final VoidCallback onOwner;
  final VoidCallback onStaff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(actions: const [LangPill(), SizedBox(width: 8)]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            // Why this person has no business any more, so it is never a mystery.
            for (final n in session.endedNotices) ...[EndedNoticeCard(notice: n), const SizedBox(height: 12)],
            for (final c in session.closedBusinesses) ...[RestoreBusinessCard(business: c), const SizedBox(height: 12)],
            Text(s.whoAreYou, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(s.whoAreYouHint, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
            const SizedBox(height: 24),
            _ChoiceCard(
              key: const Key('iAmOwner'),
              icon: Icons.storefront_rounded,
              title: s.iOwnBusiness,
              subtitle: s.iOwnBusinessHint,
              onTap: onOwner,
            ),
            const SizedBox(height: 14),
            _ChoiceCard(
              key: const Key('iAmStaff'),
              icon: Icons.badge_rounded,
              title: s.iWorkAtShop,
              subtitle: s.iWorkAtShopHint,
              onTap: onStaff,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppColors.line, width: 1.5),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: AppColors.mintDark, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

/// Staff whose number the owner hasn't added yet. "Check again" re-asks the
/// server, which links the login as soon as the owner adds this number.
class WaitingForEmployerView extends ConsumerStatefulWidget {
  const WaitingForEmployerView({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  ConsumerState<WaitingForEmployerView> createState() => _WaitingForEmployerViewState();
}

class _WaitingForEmployerViewState extends ConsumerState<WaitingForEmployerView> {
  bool _busy = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Coming back to the app (e.g. from the "You've been added" notification) checks again quietly.
    _lifecycle = AppLifecycleListener(onResume: () => _check(quiet: true));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _check({bool quiet = false}) async {
    if (_busy) return;
    final s = context.s;
    setState(() => _busy = true);
    try {
      final linked = await ref.read(authControllerProvider.notifier).recheckStaffLink();
      // When linked, the router moves on to the staff screens by itself.
      if (!linked && !quiet && mounted) showSnack(context, s.notAddedYet, error: true);
    } catch (e) {
      if (!quiet && mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final phone = ref.watch(authControllerProvider).user?.phone ?? '';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        actions: const [LangPill(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            const Center(
              child: CircleAvatar(
                radius: 44,
                backgroundColor: AppColors.amberLight,
                child: Icon(Icons.hourglass_top_rounded, size: 44, color: AppColors.amberDark),
              ),
            ),
            const SizedBox(height: 20),
            Text(s.askEmployerTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              s.askEmployerBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line, width: 1.5),
              ),
              child: Column(
                children: [
                  Text(s.yourNumber, style: const TextStyle(color: AppColors.muted)),
                  Text(
                    Phones.display(phone),
                    key: const Key('waitingPhone'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const Key('checkAgain'),
                onPressed: _busy ? null : () => _check(),
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(s.checkAgain),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => ref.read(authControllerProvider.notifier).logout(),
              child: Text(s.useAnotherNumber),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Your access to Gupta Sweets ended on 3 Oct" with the reason, dismissable.
class EndedNoticeCard extends ConsumerWidget {
  const EndedNoticeCard({super.key, required this.notice});
  final EndedNotice notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final date = notice.endedAt == null ? '' : Dates.dayMonth(notice.endedAt!.toLocal(), s.languageCode);
    return Container(
      key: Key('endedNotice-${notice.id}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.amberLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.amberBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.info_rounded, color: AppColors.amberDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date.isEmpty ? s.accessEnded(notice.companyName) : s.accessEndedOn(notice.companyName, date),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  s.endedReasonLabel(notice.reason),
                  style: const TextStyle(color: AppColors.amberDark, fontSize: 13.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: s.okGotIt,
            icon: const Icon(Icons.close_rounded, color: AppColors.amberDark),
            onPressed: () => ref.read(authControllerProvider.notifier).dismissNotice(notice.id),
          ),
        ],
      ),
    );
  }
}

/// A business this person closed, with one tap to bring it back.
class RestoreBusinessCard extends ConsumerStatefulWidget {
  const RestoreBusinessCard({super.key, required this.business});
  final ClosedBusiness business;

  @override
  ConsumerState<RestoreBusinessCard> createState() => _RestoreBusinessCardState();
}

class _RestoreBusinessCardState extends ConsumerState<RestoreBusinessCard> {
  bool _busy = false;

  Future<void> _restore() async {
    final s = context.s;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).restoreBusiness(widget.business.companyId);
      if (mounted) showSnack(context, s.restored(widget.business.companyName));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final b = widget.business;
    final until = b.restoreUntil == null ? '' : Dates.dayMonth(b.restoreUntil!.toLocal(), s.languageCode);
    return Container(
      key: Key('restore-${b.companyId}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_rounded, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.companyName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                if (until.isNotEmpty)
                  Text(s.restoreUntil(until), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: _busy ? null : _restore,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
                : Text(s.restore),
          ),
        ],
      ),
    );
  }
}

/// Staff account locked to another phone: request this one instead of a dead end.
class DeviceLockedView extends ConsumerStatefulWidget {
  const DeviceLockedView({super.key, required this.onOwnBusiness});
  final VoidCallback onOwnBusiness;

  @override
  ConsumerState<DeviceLockedView> createState() => _DeviceLockedViewState();
}

class _DeviceLockedViewState extends ConsumerState<DeviceLockedView> {
  bool _busy = false;
  final Set<String> _requested = {};

  Future<void> _request(Membership m) async {
    final s = context.s;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).requestDeviceChange(m.id);
      setState(() => _requested.add(m.id));
      if (mounted) showSnack(context, s.requestSent);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final locked = ref.watch(authControllerProvider.select((x) => x.blockedAccounts));
    return Scaffold(
      appBar: AppBar(actions: const [LangPill(), SizedBox(width: 8)]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            const Center(
              child: CircleAvatar(
                radius: 44,
                backgroundColor: AppColors.indigoLight,
                child: Icon(Icons.phonelink_lock_rounded, size: 44, color: AppColors.indigo),
              ),
            ),
            const SizedBox(height: 20),
            for (final m in locked) ...[
              Text(
                s.lockedTitle(m.companyName),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                s.lockedBody,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: _requested.contains(m.id)
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check_rounded),
                        label: Text(s.requestSent, textAlign: TextAlign.center),
                      )
                    : FilledButton.icon(
                        key: Key('requestPhone-${m.id}'),
                        onPressed: _busy ? null : () => _request(m),
                        icon: const Icon(Icons.send_to_mobile_rounded),
                        label: Text(s.requestThisPhone),
                      ),
              ),
              const SizedBox(height: 16),
            ],
            OutlinedButton(onPressed: widget.onOwnBusiness, child: Text(s.iOwnBusinessInstead)),
            TextButton(
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
              child: Text(s.useAnotherNumber),
            ),
          ],
        ),
      ),
    );
  }
}
