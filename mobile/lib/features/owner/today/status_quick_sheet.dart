import 'package:flutter/material.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_pill.dart';

/// Statuses an owner can set on a day.
const overrideStatuses = ['present', 'half_day', 'absent', 'leave', 'holiday', 'week_off'];

class StatusChoice {
  const StatusChoice({required this.status, required this.reason, this.leaveType});
  final String status;
  final String reason;
  final String? leaveType;
}

/// "Fix attendance in 2 taps": pick a reason chip (first is pre-selected),
/// tap a big status button and the sheet closes with the choice.
/// Leave asks one more tap for the leave type.
Future<StatusChoice?> showStatusQuickSheet(
  BuildContext context, {
  required DayRow row,
  required String date,
  required VoidCallback onDetails,
}) => showModalBottomSheet<StatusChoice>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (ctx) => _QuickSheet(row: row, date: date, onDetails: onDetails),
);

class _QuickSheet extends StatefulWidget {
  const _QuickSheet({required this.row, required this.date, required this.onDetails});
  final DayRow row;
  final String date;
  final VoidCallback onDetails;

  @override
  State<_QuickSheet> createState() => _QuickSheetState();
}

class _QuickSheetState extends State<_QuickSheet> {
  int _reason = 0;
  bool _pickLeaveType = false;

  void _pick(String status, {String? leaveType}) {
    final s = context.s;
    final reasons = _reasons(s);
    Navigator.pop(context, StatusChoice(status: status, reason: reasons[_reason].joined, leaveType: leaveType));
  }

  List<Bi> _reasons(S s) => [s.reasonOwnerConfirmed, s.reasonDoctor, s.reasonLateBus, s.reasonPhoneIssue];

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final row = widget.row;
    final reasons = _reasons(s);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InitialsAvatar(row.employee.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.employee.name, style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      Dates.prettyApiDate(widget.date, s.languageCode),
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              StatusPill(status: row.displayStatus),
            ],
          ),
          const SizedBox(height: 14),
          Text(s.reason, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < reasons.length; i++)
                ChoiceChip(
                  key: Key('quickReason_$i'),
                  label: Text(reasons[i].joined),
                  selected: _reason == i,
                  showCheckmark: false,
                  selectedColor: AppColors.ink,
                  labelStyle: TextStyle(
                    color: _reason == i ? Colors.white : AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (_) => setState(() => _reason = i),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_pickLeaveType)
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.35,
              children: [
                for (final st in overrideStatuses)
                  _StatusButton(
                    key: Key('quickStatus_$st'),
                    status: st,
                    current: row.record?.status == st,
                    onTap: () => st == 'leave' ? setState(() => _pickLeaveType = true) : _pick(st),
                  ),
              ],
            )
          else ...[
            Text(s.leaveTypeTitle, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final t in const ['paid', 'sick', 'unpaid']) ...[
                  if (t != 'paid') const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: Key('quickLeave_$t'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.indigoLight,
                        foregroundColor: AppColors.indigo,
                        minimumSize: const Size(48, 60),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      onPressed: () => _pick('leave', leaveType: t),
                      child: Text(s.leaveTypeLabel(t), textAlign: TextAlign.center),
                    ),
                  ),
                ],
              ],
            ),
            TextButton(onPressed: () => setState(() => _pickLeaveType = false), child: Text(s.back)),
          ],
          const SizedBox(height: 10),
          Text(
            s.tapStatusHint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
          ),
          TextButton.icon(
            key: const Key('quickDetails'),
            onPressed: () {
              Navigator.pop(context);
              widget.onDetails();
            },
            icon: const Icon(Icons.receipt_long_rounded),
            label: Text(s.details),
          ),
        ],
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({super.key, required this.status, required this.current, required this.onTap});
  final String status;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final st = StatusStyle.of(status);
    return Material(
      color: st.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: current ? const BorderSide(color: AppColors.ink, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(st.icon, color: st.fg, size: 26),
            const SizedBox(height: 2),
            Text(
              context.s.statusShort(status),
              textAlign: TextAlign.center,
              style: TextStyle(color: st.fg, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
