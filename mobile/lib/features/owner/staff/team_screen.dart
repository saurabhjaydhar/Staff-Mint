import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../more/accountants_screen.dart' show accountantsProvider;
import '../more/owners_screen.dart' show ownersProvider;
import '../providers/owner_providers.dart';

const _activeStaff = (search: '', status: 'active');

/// Everything about "who can open your business", in one place: partners,
/// managers and the CA, each with one line on what they can and can't do.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final owners = ref.watch(ownersProvider);
    final staff = ref.watch(employeesProvider(_activeStaff));
    final cas = ref.watch(accountantsProvider);
    final managers = (staff.value ?? const <Employee>[]).where((e) => e.isManager).toList();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.teamAccess),
            Text(s.teamWho, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          ],
        ),
      ),
      body: RefreshableList(
        onRefresh: () {
          ref.invalidate(ownersProvider);
          ref.invalidate(accountantsProvider);
          return ref.refresh(employeesProvider(_activeStaff).future);
        },
        children: [
          _Section(
            key: const Key('teamPartners'),
            icon: Icons.handshake_rounded,
            title: s.partnersTitle,
            can: s.partnersCan,
            people: [
              for (final o in owners.value ?? const <OwnerItem>[])
                _Person(name: o.isYou ? s.youLabel : o.name, role: o.isMain ? s.mainOwnerLabel : s.partnerLabel),
            ],
            action: s.addPartner,
            onAction: () => context.push(Routes.ownerOwners),
          ),
          _Section(
            key: const Key('teamManagers'),
            icon: Icons.manage_accounts_rounded,
            title: s.managersTitle,
            can: s.managersCan,
            empty: s.noManagers,
            people: [
              for (final m in managers)
                _Person(
                  name: m.name,
                  role: m.designation,
                  trailing: TextButton(
                    key: Key('backToStaff_${m.id}'),
                    onPressed: () => confirmBackToStaff(context, ref, m),
                    child: Text(s.backToStaff),
                  ),
                ),
            ],
            action: s.makeManagerAction,
            actionKey: const Key('makeManagerAction'),
            onAction: () => pickAndMakeManager(context, ref),
          ),
          _Section(
            key: const Key('teamCa'),
            icon: Icons.calculate_rounded,
            title: s.caTitle,
            can: s.caCan,
            people: [for (final a in cas.value ?? const <Accountant>[]) _Person(name: a.name, role: 'CA')],
            action: (cas.value ?? const []).isEmpty ? s.addCa : s.manage,
            onAction: () => context.push(Routes.ownerAccountants),
          ),
        ],
      ),
    );
  }
}

class _Person {
  const _Person({required this.name, this.role, this.trailing});
  final String name;
  final String? role;
  final Widget? trailing;
}

class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.icon,
    required this.title,
    required this.can,
    required this.people,
    required this.action,
    required this.onAction,
    this.actionKey,
    this.empty,
  });
  final IconData icon;
  final String title;
  final String can;
  final List<_Person> people;
  final String action;
  final VoidCallback onAction;
  final Key? actionKey;
  final String? empty;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.mintDark),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 4),
          Text(can, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
          const SizedBox(height: 6),
          if (people.isEmpty && empty != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(empty!, style: const TextStyle(color: AppColors.muted)),
            ),
          for (final p in people)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: InitialsAvatar(p.name),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: p.role == null || p.role!.isEmpty ? null : Text(p.role!),
              trailing: p.trailing,
            ),
          TextButton.icon(
            key: actionKey,
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded),
            label: Text(action),
          ),
        ],
      ),
    ),
  );
}

/// Pick a staff member, then show what a manager can and can't do before confirming.
Future<void> pickAndMakeManager(BuildContext context, WidgetRef ref) async {
  final s = context.s;
  final staff = (await ref.read(employeesProvider(_activeStaff).future)).where((e) => !e.isManager).toList();
  if (!context.mounted) return;
  final picked = await showModalBottomSheet<Employee>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(s.pickStaff, style: Theme.of(ctx).textTheme.titleLarge),
        ),
        for (final e in staff)
          ListTile(
            key: Key('pickManager_${e.id}'),
            leading: InitialsAvatar(e.name),
            title: Text(e.name),
            subtitle: e.designation == null ? null : Text(e.designation!),
            onTap: () => Navigator.pop(ctx, e),
          ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return;
  await showMakeManagerSheet(context, ref, picked);
}

/// "Make Ramesh a manager?": clear can / can't before confirming, so owners feel safe.
Future<void> showMakeManagerSheet(BuildContext context, WidgetRef ref, Employee e) async {
  final branches = await ref.read(branchesProvider.future).catchError((_) => const <Branch>[]);
  if (!context.mounted) return;
  final allBranches = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _MakeManagerSheet(employee: e, manyBranches: branches.length > 1),
  );
  if (allBranches == null || !context.mounted) return;
  final s = context.s;
  final ok = await runGuarded(
    context,
    () => ref.read(employeesApiProvider).setRole(e.id, 'manager', allBranches: allBranches),
    success: s.madeManager(e.name),
  );
  if (ok) ref.invalidate(employeesProvider);
}

Future<void> confirmBackToStaff(BuildContext context, WidgetRef ref, Employee e) async {
  final s = context.s;
  if (!await confirmDialog(context, title: s.backToStaff, message: s.backToStaffQ(e.name))) return;
  if (!context.mounted) return;
  final ok = await runGuarded(
    context,
    () => ref.read(employeesApiProvider).setRole(e.id, 'employee'),
    success: s.backToStaffDone(e.name),
  );
  if (ok) ref.invalidate(employeesProvider);
}

class _MakeManagerSheet extends StatefulWidget {
  const _MakeManagerSheet({required this.employee, required this.manyBranches});
  final Employee employee;
  final bool manyBranches;

  @override
  State<_MakeManagerSheet> createState() => _MakeManagerSheetState();
}

class _MakeManagerSheetState extends State<_MakeManagerSheet> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    Widget line(bool yes, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            yes ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 20,
            color: yes ? AppColors.mint : AppColors.red,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.makeManagerQ(widget.employee.name), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(s.willBeAbleTo, style: const TextStyle(fontWeight: FontWeight.w700)),
          line(true, s.canSeeFix),
          line(true, s.canApproveLeave),
          line(true, s.canApprovePhones),
          const SizedBox(height: 10),
          Text(s.wontSee, style: const TextStyle(fontWeight: FontWeight.w700)),
          line(false, s.cantSalary),
          line(false, s.cantSettings),
          if (widget.manyBranches) ...[
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(s.ownBranchLabel)),
                ButtonSegment(value: true, label: Text(s.allBranchesLabel)),
              ],
              selected: {_all},
              onSelectionChanged: (v) => setState(() => _all = v.first),
            ),
          ],
          const SizedBox(height: 12),
          Text(s.managerMessageNote, style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('confirmMakeManager'),
            onPressed: () => Navigator.pop(context, _all),
            child: Text(s.makeManager),
          ),
        ],
      ),
    );
  }
}
