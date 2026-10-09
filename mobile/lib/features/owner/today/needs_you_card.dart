import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../providers/owner_providers.dart';
import 'leave_cards.dart';

/// Dark "N काम आपके लिए" card that expands into the actionable list:
/// swipeable leave requests and outside-shop punch approvals.
class NeedsYouCard extends ConsumerStatefulWidget {
  const NeedsYouCard({super.key, required this.dashboard});
  final Dashboard dashboard;

  @override
  ConsumerState<NeedsYouCard> createState() => _NeedsYouCardState();
}

class _NeedsYouCardState extends ConsumerState<NeedsYouCard> {
  bool _open = false;

  /// Decided items disappear at once, before the dashboard refetches.
  final Set<String> _handled = {};
  final Set<String> _busy = {};

  Future<bool> _run(String id, bool approve, Future<void> Function() call) async {
    setState(() => _busy.add(id));
    final s = context.s;
    final ok = await runGuarded(context, call, success: approve ? s.approved : s.rejected);
    if (!mounted) return ok;
    setState(() => _busy.remove(id));
    if (ok) invalidateAttendance(ref);
    return ok;
  }

  Future<bool> _decideLeave(Leave l, bool approve) =>
      _run(l.id, approve, () => ref.read(leaveApiProvider).decide(l.id, approve: approve));

  Future<bool> _decidePunch(PunchApprovalItem p, bool approve) =>
      _run(p.punch.id, approve, () => ref.read(attendanceApiProvider).decidePunch(p.attendanceId, p.punch.id, approve));

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = widget.dashboard;
    final leaves = d.leaveRequests.where((l) => !_handled.contains(l.id)).toList();
    final punches = d.punchApprovals.where((p) => !_handled.contains(p.punch.id)).toList();
    final count = leaves.length + punches.length + d.flags.length;
    if (count == 0) return const SizedBox.shrink();
    final names = [
      for (final l in leaves) s.needsYouLeave(l.employeeName),
      for (final p in punches) s.needsYouPunch(p.employeeName),
      for (final f in d.flags) s.needsYouFlag(f.employeeName),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('needsYouCard'),
          margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(18)),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.needsYouTitle(count).joined,
                          style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          names.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _open ? s.hide : s.view,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          _open ? Icons.expand_less_rounded : Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (leaves.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: Text(s.swipeHint, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                      ),
                    for (final l in leaves)
                      SwipeToDecide(
                        id: l.id,
                        onSwipe: (approve) => _decideLeave(l, approve),
                        onDismissed: () => setState(() => _handled.add(l.id)),
                        child: LeaveDecisionCard(
                          leave: l,
                          busy: _busy.contains(l.id),
                          onDecide: (a) async {
                            if (await _decideLeave(l, a) && mounted) setState(() => _handled.add(l.id));
                          },
                        ),
                      ),
                    for (final p in punches)
                      _PunchApprovalCard(
                        item: p,
                        busy: _busy.contains(p.punch.id),
                        onDecide: (a) async {
                          if (await _decidePunch(p, a) && mounted) setState(() => _handled.add(p.punch.id));
                        },
                      ),
                    for (final f in d.flags)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.flag_rounded, color: AppColors.amberDark),
                          title: Text(f.employeeName),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(Dates.prettyApiDate(f.date, s.languageCode)),
                              const SizedBox(height: 4),
                              FlagChips(flags: f.flags),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PunchApprovalCard extends StatelessWidget {
  const _PunchApprovalCard({required this.item, required this.busy, required this.onDecide});
  final PunchApprovalItem item;
  final bool busy;
  final ValueChanged<bool> onDecide;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = item.punch;
    final outside = p.insideGeofence == false || p.mockLocation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: p.selfieUrl == null
                      ? Container(
                          width: 52,
                          height: 52,
                          color: AppColors.amberLight,
                          child: Icon(
                            outside ? Icons.wrong_location_rounded : Icons.lock_open_rounded,
                            color: AppColors.amberDark,
                          ),
                        )
                      : Image.network(
                          p.selfieUrl!,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(width: 52, height: 52, child: Icon(Icons.person)),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.employeeName, style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        '${outside ? s.outsidePunchApproval : s.lockPunchApproval} · ${p.isIn ? s.checkInLabel : s.checkOutLabel} ${Dates.time(p.clientTime, s.languageCode)}',
                      ),
                      if (p.distanceM != null)
                        Text(s.distanceAway(p.distanceM!), style: const TextStyle(color: AppColors.red)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DecisionButtons(busy: busy, onDecide: onDecide),
          ],
        ),
      ),
    );
  }
}
