import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/bilingual.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_controller.dart';
import '../setup/setup_screen.dart' show businessIcons;
import '../setup/who_are_you.dart' show RestoreBusinessCard;

/// Opens [m] on this phone and lands on its home screen. Shared by the
/// chooser and the Profile list. Returns true when the account changed.
Future<bool> openAccount(BuildContext context, WidgetRef ref, Membership m) async {
  final s = context.s;
  if (m.lockedToOtherPhone) {
    await askToRequestPhone(context, ref, m);
    return false;
  }
  final ctrl = ref.read(authControllerProvider.notifier);
  final wasActive = ref.read(authControllerProvider).activeMembershipId == m.id;
  try {
    await ctrl.chooseAccount(m.id);
  } on PendingPunchesException catch (e) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.cloud_upload_rounded, color: AppColors.amberDark, size: 32),
          title: Text(s.switchAccount),
          content: Text(s.pendingPunchesBlock(e.count)),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(s.ok))],
        ),
      );
    }
    return false;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
  if (!context.mounted) return !wasActive;
  final session = ref.read(authControllerProvider);
  if (!wasActive) showSnack(context, s.switchedTo(m.companyName));
  context.go(session.isEmployee ? Routes.employeeHome : Routes.ownerHome);
  return !wasActive;
}

/// Staff account bound to another phone: explain, and send the owner a request.
Future<void> askToRequestPhone(BuildContext context, WidgetRef ref, Membership m) async {
  final s = context.s;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.phonelink_lock_rounded, color: AppColors.indigo, size: 32),
      title: Text(s.lockedTitle(m.companyName)),
      content: Text(s.lockedBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.requestThisPhone)),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(authControllerProvider.notifier).requestDeviceChange(m.id);
    if (context.mounted) showSnack(context, s.requestSent);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// "Which business?" — after login with more than one account, and from
/// Profile → Switch account.
class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  String? _busyId;
  String _query = '';

  /// Search appears for accountants and others with many businesses.
  static const searchFrom = 7;

  Future<void> _open(Membership m) async {
    setState(() => _busyId = m.id);
    try {
      await openAccount(context, ref, m);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    final forced = session.needsAccountChoice;
    final ownsOne = session.memberships.any((m) => m.role == 'owner');
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: forced
            ? null
            : IconButton(
                key: const Key('accountsClose'),
                icon: const Icon(Icons.close_rounded),
                onPressed: () => context.canPop() ? context.pop() : context.go(Routes.splash),
              ),
        actions: const [LangPill(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(forced ? s.chooseAccount : s.switchAccount, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              s.chooseAccountHint(Phones.display(session.user?.phone ?? '')),
              style: const TextStyle(color: AppColors.muted, fontSize: 15),
            ),
            const SizedBox(height: 20),
            const AccountAlerts(padding: EdgeInsets.zero),
            if (session.memberships.length >= searchFrom) ...[
              TextField(
                key: const Key('accountSearch'),
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: s.searchBusinesses),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
            ],
            // Pinned first, otherwise most recently used first (server order).
            for (final m in [
              ...session.memberships.where((m) => m.pinned),
              ...session.memberships.where((m) => !m.pinned),
            ].where((m) => _query.isEmpty || m.companyName.toLowerCase().contains(_query))) ...[
              AccountCard(
                key: Key('account-${m.id}'),
                membership: m,
                active: m.id == session.activeMembershipId,
                busy: _busyId == m.id,
                onTap: _busyId == null ? () => _open(m) : null,
                onPin: session.memberships.length > 2
                    ? () => ref.read(authControllerProvider.notifier).pinAccount(m.id, pinned: !m.pinned).catchError((
                        Object e,
                      ) {
                        if (context.mounted) showError(context, e);
                      })
                    : null,
              ),
              const SizedBox(height: 12),
            ],
            for (final c in session.closedBusinesses) ...[RestoreBusinessCard(business: c), const SizedBox(height: 12)],
            const SizedBox(height: 4),
            _NewBusinessTile(
              label: ownsOne ? s.addAnotherBusiness : s.startOwnBusiness,
              hint: s.ownBusinessHint,
              onTap: _busyId == null ? () => context.push(Routes.accountsNew) : null,
            ),
            const SizedBox(height: 28),
            Text(
              s.accountsFooter,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            if (forced) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _busyId == null ? () => ref.read(authControllerProvider.notifier).logout() : null,
                  child: Text(s.logout, style: const TextStyle(color: AppColors.muted)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Colours per role, so "Owner" and "Staff" read differently at a glance.
(Color, Color) roleColors(String role) => switch (role) {
  'owner' => (AppColors.mintLight, AppColors.mintDark),
  'manager' => (AppColors.indigoLight, AppColors.indigo),
  'ca' => (AppColors.orangeLight, AppColors.orange),
  _ => (AppColors.amberLight, AppColors.amberDark),
};

class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.membership,
    required this.active,
    this.busy = false,
    this.onTap,
    this.onPin,
  });
  final Membership membership;
  final bool active;
  final bool busy;
  final VoidCallback? onTap;

  /// Star to keep this business at the top (shown when there are several).
  final VoidCallback? onPin;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final m = membership;
    final (chipBg, chipFg) = roleColors(m.role);
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? AppColors.mintFaint : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: active ? AppColors.mint : AppColors.line, width: active ? 1.8 : 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: active ? AppColors.mint : AppColors.mintLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    businessIcons[m.businessType] ?? Icons.storefront_rounded,
                    color: active ? Colors.white : AppColors.mintDark,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.companyName.isEmpty ? s.businessTypeLabel(m.businessType ?? 'other') : m.companyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(20)),
                            child: Text(
                              s.roleLabel(m.role),
                              style: TextStyle(color: chipFg, fontWeight: FontWeight.w700, fontSize: 12.5),
                            ),
                          ),
                          if (m.lockedToOtherPhone)
                            Text(
                              s.lockedToOtherPhone,
                              style: const TextStyle(
                                color: AppColors.indigo,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (active)
                            Text(
                              s.openNow,
                              style: const TextStyle(
                                color: AppColors.mintDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (onPin != null)
                  IconButton(
                    key: Key('pin-${m.id}'),
                    tooltip: m.pinned ? s.unpin : s.pin,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      m.pinned ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: m.pinned ? AppColors.amber : AppColors.muted,
                    ),
                    onPressed: onPin,
                  ),
                if (busy)
                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                else if (active)
                  const Icon(Icons.check_circle_rounded, color: AppColors.mint)
                else
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewBusinessTile extends StatelessWidget {
  const _NewBusinessTile({required this.label, required this.hint, this.onTap});
  final String label;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('newBusiness'),
    color: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppColors.mint, width: 1.4, style: BorderStyle.solid),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: AppColors.mintFaint, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.add_business_rounded, color: AppColors.mintDark, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppColors.mintDark),
                  ),
                  const SizedBox(height: 2),
                  Text(hint, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// "Gupta Sweets ▾" under a home header when this number has several
/// accounts: one tap to switch, and staff at two shops always see which one
/// they are checking in to.
class BusinessSwitchChip extends ConsumerWidget {
  const BusinessSwitchChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider);
    if (!session.hasManyAccounts) return const SizedBox.shrink();
    final m = session.activeMembership;
    final s = context.s;
    final name = m?.companyName ?? session.company?.name ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          label: '${s.switchAccount}: $name',
          child: Material(
            color: AppColors.mintFaint,
            shape: const StadiumBorder(side: BorderSide(color: AppColors.mintLight, width: 1.4)),
            child: InkWell(
              key: const Key('businessChip'),
              customBorder: const StadiumBorder(),
              onTap: () => context.push(Routes.accounts),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      businessIcons[m?.businessType] ?? Icons.storefront_rounded,
                      size: 18,
                      color: AppColors.mintDark,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.mintDark),
                      ),
                    ),
                    if (m != null) ...[
                      const SizedBox(width: 6),
                      Text('· ${s.roleLabel(m.role)}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                    ],
                    const Icon(Icons.arrow_drop_down_rounded, color: AppColors.mintDark),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Things only this person can act on, shown at the top of home screens:
/// offers to become an owner, and recoveries they may stop.
class AccountAlerts extends ConsumerStatefulWidget {
  const AccountAlerts({super.key, this.padding = const EdgeInsets.fromLTRB(14, 6, 14, 6)});
  final EdgeInsets padding;

  @override
  ConsumerState<AccountAlerts> createState() => _AccountAlertsState();
}

class _AccountAlertsState extends ConsumerState<AccountAlerts> {
  String? _busy;

  Future<void> _run(String id, Future<void> Function() action, {String? done}) async {
    setState(() => _busy = id);
    try {
      await action();
      if (mounted && done != null) showSnack(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    final ctrl = ref.read(authControllerProvider.notifier);
    if (session.pendingTransfers.isEmpty && session.recoveryHolds.isEmpty) return const SizedBox.shrink();
    Widget card({
      required Key key,
      required IconData icon,
      required Color color,
      required Color bg,
      required String title,
      required String body,
      required List<Widget> actions,
    }) => Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(body, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
                  ],
                ),
              ),
            ],
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
        ],
      ),
    );
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in session.pendingTransfers)
            card(
              key: Key('offer-${t.id}'),
              icon: Icons.workspace_premium_rounded,
              color: AppColors.mintDark,
              bg: AppColors.mintFaint,
              title: s.offerTitle(t.companyName),
              body: s.offerBody(t.fromName),
              actions: [
                TextButton(
                  onPressed: _busy == null ? () => _run(t.id, () => ctrl.decideTransfer(t.id, accept: false)) : null,
                  child: Text(s.decline),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  key: Key('acceptOffer-${t.id}'),
                  onPressed: _busy == null ? () => _run(t.id, () => ctrl.decideTransfer(t.id, accept: true)) : null,
                  child: _busy == t.id
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                        )
                      : Text(s.accept),
                ),
              ],
            ),
          for (final h in session.recoveryHolds)
            card(
              key: Key('hold-${h.id}'),
              icon: Icons.gpp_maybe_rounded,
              color: AppColors.red,
              bg: AppColors.redLight,
              title: s.holdTitle(h.businessName),
              body: s.holdBody(h.holdUntil == null ? '' : Dates.dayMonth(h.holdUntil!.toLocal(), s.languageCode)),
              actions: [
                FilledButton(
                  key: Key('stopHold-${h.id}'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                  onPressed: _busy == null ? () => _run(h.id, () => ctrl.stopRecovery(h.id), done: s.stopped) : null,
                  child: Text(s.stop),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
