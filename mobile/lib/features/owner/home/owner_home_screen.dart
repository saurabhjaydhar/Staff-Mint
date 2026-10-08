import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_controller.dart';
import '../providers/owner_providers.dart';
import '../salary/money_dialogs.dart';

class OwnerHomeScreen extends ConsumerWidget {
  const OwnerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    final dash = ref.watch(dashboardProvider);
    Future<void> refresh() => ref.refresh(dashboardProvider.future);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.company?.name ?? s.appName),
            Text(
              s.hello(session.user?.name ?? ''),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
          ],
        ),
        toolbarHeight: 72,
      ),
      body: AsyncBody<Dashboard>(
        value: dash,
        onRetry: () => ref.invalidate(dashboardProvider),
        data: (d) => RefreshableList(
          onRefresh: refresh,
          children: [
            SectionHeader(
              s.todayAtAGlance,
              trailing: Text(
                Dates.prettyApiDate(d.date, s.languageCode),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
            ),
            _CountsGrid(counts: d.counts),
            if (d.staffLimit > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  s.staffUsage(d.staffCount, d.staffLimit),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: d.staffCount >= d.staffLimit ? AppColors.absent : Colors.black54),
                ),
              ),
            SectionHeader(s.quickActions),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _QuickAction(
                    icon: Icons.fact_check_rounded,
                    label: s.markAttendance,
                    onTap: () => context.go(Routes.ownerAttendance),
                  ),
                  _QuickAction(
                    icon: Icons.payments_rounded,
                    label: s.addAdvance,
                    onTap: () async {
                      if (await showAddAdvanceSheet(context, ref) && context.mounted) {
                        ref.invalidate(dashboardProvider);
                      }
                    },
                  ),
                  _QuickAction(
                    icon: Icons.person_add_alt_1_rounded,
                    label: s.addStaff,
                    onTap: () => context.push(Routes.ownerStaffAdd),
                  ),
                ],
              ),
            ),
            SectionHeader(
              s.needsAction,
              trailing: d.needsActionCount > 0
                  ? Badge(label: Text('${d.needsActionCount}'), backgroundColor: AppColors.absent)
                  : null,
            ),
            if (d.needsActionCount == 0)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_rounded, color: AppColors.mint, size: 32),
                  title: Text(s.allCaughtUp),
                ),
              ),
            for (final l in d.leaveRequests) _LeaveRequestCard(leave: l),
            for (final p in d.punchApprovals) _PunchApprovalCard(item: p),
            for (final f in d.flags)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.flag_rounded, color: AppColors.late),
                  title: Text(f.employeeName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(Dates.prettyApiDate(f.date, s.languageCode)),
                      const SizedBox(height: 4),
                      FlagChips(flags: f.flags),
                    ],
                  ),
                  onTap: () => context.go(Routes.ownerAttendance),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CountsGrid extends StatelessWidget {
  const _CountsGrid({required this.counts});
  final DashboardCounts counts;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final tiles = [
      (s.countPresent, counts.present, AppColors.present),
      (s.countLate, counts.late, AppColors.late),
      (s.countAbsent, counts.absent, AppColors.absent),
      (s.countOnLeave, counts.onLeave, AppColors.leave),
      (s.countNotMarked, counts.notMarked, Colors.blueGrey),
      (s.countCheckedIn, counts.checkedIn, AppColors.checkedIn),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.15,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          for (final (label, value, color) in tiles)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.go(Routes.ownerAttendance),
              child: Container(
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$value',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Color.lerp(color, Colors.black, 0.2),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE3E8E5)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.mintLight,
                  child: Icon(icon, color: AppColors.mintDark),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _LeaveRequestCard extends ConsumerStatefulWidget {
  const _LeaveRequestCard({required this.leave});
  final Leave leave;

  @override
  ConsumerState<_LeaveRequestCard> createState() => _LeaveRequestCardState();
}

class _LeaveRequestCardState extends ConsumerState<_LeaveRequestCard> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    final s = context.s;
    final ok = await runGuarded(
      context,
      () => ref.read(leaveApiProvider).decide(widget.leave.id, approve: approve),
      success: approve ? s.approved : s.rejected,
    );
    if (ok && mounted) invalidateAttendance(ref);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final l = widget.leave;
    return LeaveDecisionCard(leave: l, busy: _busy, onDecide: _decide, s: s);
  }
}

/// Shared leave card with Approve / Reject buttons.
class LeaveDecisionCard extends StatelessWidget {
  const LeaveDecisionCard({
    super.key,
    required this.leave,
    required this.busy,
    required this.onDecide,
    required this.s,
  });
  final Leave leave;
  final bool busy;
  final ValueChanged<bool> onDecide;
  final S s;

  @override
  Widget build(BuildContext context) {
    final l = leave;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.beach_access_rounded, color: AppColors.leave),
                const SizedBox(width: 8),
                Expanded(child: Text(l.employeeName, style: Theme.of(context).textTheme.titleMedium)),
                if (!l.isPending) Text(s.leaveStatusLabel(l.status)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              s.leaveRequestLine(
                s.leaveTypeLabel(l.type),
                Dates.prettyApiDate(l.from, s.languageCode),
                Dates.prettyApiDate(l.to, s.languageCode),
                l.days,
              ),
            ),
            if (l.reason != null && l.reason!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '“${l.reason}”',
                style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black54),
              ),
            ],
            if (l.isPending) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.absent),
                      onPressed: busy ? null : () => onDecide(false),
                      child: Text(s.reject),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(onPressed: busy ? null : () => onDecide(true), child: Text(s.approve)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PunchApprovalCard extends ConsumerStatefulWidget {
  const _PunchApprovalCard({required this.item});
  final PunchApprovalItem item;

  @override
  ConsumerState<_PunchApprovalCard> createState() => _PunchApprovalCardState();
}

class _PunchApprovalCardState extends ConsumerState<_PunchApprovalCard> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    final s = context.s;
    final ok = await runGuarded(
      context,
      () => ref.read(attendanceApiProvider).decidePunch(widget.item.attendanceId, widget.item.punch.id, approve),
      success: approve ? s.approved : s.rejected,
    );
    if (ok && mounted) invalidateAttendance(ref);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = widget.item.punch;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (p.selfieUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      p.selfieUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.person, size: 48),
                    ),
                  )
                else
                  const Icon(Icons.wrong_location_rounded, color: AppColors.late, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.item.employeeName, style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        '${s.outsidePunchApproval} · ${p.isIn ? s.checkInLabel : s.checkOutLabel} ${Dates.time(p.clientTime, s.languageCode)}',
                      ),
                      if (p.distanceM != null)
                        Text(s.distanceAway(p.distanceM!), style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.absent),
                    onPressed: _busy ? null : () => _decide(false),
                    child: Text(s.reject),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(onPressed: _busy ? null : () => _decide(true), child: Text(s.approve)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
