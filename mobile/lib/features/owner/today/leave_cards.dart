import 'package:flutter/material.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';

/// Leave request with explicit Reject / Approve buttons.
class LeaveDecisionCard extends StatelessWidget {
  const LeaveDecisionCard({
    super.key,
    required this.leave,
    required this.busy,
    required this.onDecide,
    this.onApproveUnpaid,
  });
  final Leave leave;
  final bool busy;
  final ValueChanged<bool> onDecide;

  /// Approve as unpaid leave — offered when there aren't enough paid/sick leaves left.
  final VoidCallback? onApproveUnpaid;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final l = leave;
    // Not enough paid/sick leave left for these days.
    final short = l.type != 'unpaid' && l.balanceAfter != null && l.balanceAfter! < 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: AppColors.indigoLight, shape: BoxShape.circle),
                  child: const Icon(Icons.beach_access_rounded, color: AppColors.indigo, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.isPending ? s.wantsLeave(l.employeeName) : l.employeeName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!l.isPending)
                  Text(
                    s.leaveStatusLabel(l.status),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: l.status == 'approved'
                          ? AppColors.mint
                          : l.status == 'rejected'
                          ? AppColors.red
                          : AppColors.muted,
                    ),
                  ),
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
                style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.muted),
              ),
            ],
            if (l.isPending && l.balanceLeft != null && l.balanceAfter != null && !short) ...[
              const SizedBox(height: 4),
              Text(
                s.leavesAfter(s.leaveKind(l.type), l.balanceLeft!, l.balanceAfter!),
                key: Key('leaveEffect_${l.id}'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (l.isPending && short) ...[
              const SizedBox(height: 8),
              Container(
                key: Key('leaveShort_${l.id}'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.redLight, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  l.balanceLeft! <= 0
                      ? s.noLeavesLeft(s.leaveKind(l.type), l.days)
                      : s.fewLeavesLeft(s.leaveKind(l.type), l.balanceLeft!, l.days),
                  style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            if (l.isPending) ...[
              const SizedBox(height: 10),
              if (short && onApproveUnpaid != null) ...[
                // The main button says exactly what happens: these days are unpaid.
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: Key('leaveUnpaid_${l.id}'),
                    onPressed: busy ? null : onApproveUnpaid,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(s.approveAsUnpaid),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    key: Key('leaveNo_${l.id}'),
                    onPressed: busy ? null : () => onDecide(false),
                    child: Text(s.sayNo),
                  ),
                ),
                Center(
                  child: TextButton(
                    key: Key('leavePaidAnyway_${l.id}'),
                    onPressed: busy ? null : () => onDecide(true),
                    child: Text(s.giveAsPaid),
                  ),
                ),
              ] else
                DecisionButtons(busy: busy, onDecide: onDecide, rejectLabel: s.sayNo),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reject (red outline) + Approve (mint) pair.
class DecisionButtons extends StatelessWidget {
  const DecisionButtons({super.key, required this.busy, required this.onDecide, this.rejectLabel, this.approveLabel});
  final bool busy;
  final ValueChanged<bool> onDecide;

  /// Overrides "Reject" (e.g. "Ask for a new photo").
  final String? rejectLabel;

  /// Overrides "Approve" (e.g. "Count it"), so each button says exactly what it does.
  final String? approveLabel;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: AppColors.red, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onPressed: busy ? null : () => onDecide(false),
            icon: const Icon(Icons.close_rounded),
            label: FittedBox(fit: BoxFit.scaleDown, child: Text(rejectLabel ?? s.reject, maxLines: 1)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
            onPressed: busy ? null : () => onDecide(true),
            icon: const Icon(Icons.check_rounded),
            label: FittedBox(fit: BoxFit.scaleDown, child: Text(approveLabel ?? s.approve, maxLines: 1)),
          ),
        ),
      ],
    );
  }
}

/// Swipe right = approve, swipe left = reject. [onSwipe] returns whether the
/// decision was saved; only then does the card leave the list.
class SwipeToDecide extends StatelessWidget {
  const SwipeToDecide({
    super.key,
    required this.id,
    required this.onSwipe,
    required this.onDismissed,
    required this.child,
  });
  final String id;
  final Future<bool> Function(bool approve) onSwipe;
  final VoidCallback onDismissed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    Widget bg(bool approve) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: approve ? AppColors.mint : AppColors.red, borderRadius: AppTheme.radius),
      alignment: approve ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(approve ? Icons.check_rounded : Icons.close_rounded, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            approve ? s.approve : s.reject,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
    return Dismissible(
      key: ValueKey('swipe_$id'),
      background: bg(true),
      secondaryBackground: bg(false),
      confirmDismiss: (dir) => onSwipe(dir == DismissDirection.startToEnd),
      onDismissed: (_) => onDismissed(),
      child: child,
    );
  }
}
