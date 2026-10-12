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
  const StatusChoice({required this.status, this.reason, this.leaveType});
  final String status;

  /// Optional: the owner picks what happened first, and may say why.
  final String? reason;
  final String? leaveType;
}

/// "What happened this day?": pick a status (each with what it means for
/// pay), optionally a reason, then Save. Nothing changes until Save.
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
  String? _status;
  String _leaveType = 'paid';
  int? _reason;
  final _written = TextEditingController();
  bool _writing = false;

  @override
  void dispose() {
    _written.dispose();
    super.dispose();
  }

  List<Bi> _reasons(S s) => [s.reasonLateBus, s.reasonDoctor, s.reasonPhoneIssue, s.reasonOwnerConfirmed];

  void _save() {
    final s = context.s;
    final typed = _written.text.trim();
    final reason = _writing && typed.isNotEmpty ? typed : (_reason == null ? null : _reasons(s)[_reason!].joined);
    Navigator.pop(
      context,
      StatusChoice(status: _status!, reason: reason, leaveType: _status == 'leave' ? _leaveType : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final row = widget.row;
    final reasons = _reasons(s);
    final firstIn = row.record?.firstIn;
    final when = [
      Dates.prettyApiDate(widget.date, s.languageCode),
      if (firstIn != null) s.cameInAt(Dates.clock(firstIn.clientTime)),
    ].join(' · ');
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 16 + MediaQuery.viewInsetsOf(context).bottom),
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
                    Text(when, style: const TextStyle(color: AppColors.muted)),
                  ],
                ),
              ),
              StatusPill(status: row.displayStatus),
            ],
          ),
          const SizedBox(height: 14),
          Text(s.whatHappened, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.2,
            children: [
              for (final st in overrideStatuses)
                _StatusButton(
                  key: Key('quickStatus_$st'),
                  status: st,
                  selected: _status == st,
                  current: row.record?.status == st,
                  onTap: () => setState(() => _status = st),
                ),
            ],
          ),
          if (_status == 'leave') ...[
            const SizedBox(height: 12),
            Text(s.leaveTypeTitle, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final t in const ['paid', 'sick', 'unpaid'])
                  ChoiceChip(
                    key: Key('quickLeave_$t'),
                    label: Text(s.leaveTypeLabel(t)),
                    selected: _leaveType == t,
                    onSelected: (_) => setState(() => _leaveType = t),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Text(s.reasonOptional, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < reasons.length; i++)
                ChoiceChip(
                  key: Key('quickReason_$i'),
                  label: Text(reasons[i].joined),
                  selected: !_writing && _reason == i,
                  onSelected: (on) => setState(() {
                    _writing = false;
                    _reason = on ? i : null;
                  }),
                ),
              ChoiceChip(
                key: const Key('quickReasonWrite'),
                avatar: const Icon(Icons.edit_rounded, size: 16),
                label: Text(s.writeReason),
                selected: _writing,
                onSelected: (on) => setState(() => _writing = on),
              ),
            ],
          ),
          if (_writing) ...[
            const SizedBox(height: 8),
            TextField(
              key: const Key('quickReasonText'),
              controller: _written,
              autofocus: true,
              maxLength: 300,
              decoration: InputDecoration(labelText: s.reason),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  key: const Key('quickDetails'),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onDetails();
                  },
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(s.seePhotoMap, textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('quickSave'),
                onPressed: _status == null ? null : _save,
                child: Text(_status == null ? s.pickStatusFirst : s.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    super.key,
    required this.status,
    required this.selected,
    required this.current,
    required this.onTap,
  });
  final String status;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final st = StatusStyle.of(status);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: st.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: selected
              ? const BorderSide(color: AppColors.ink, width: 2.5)
              : current
              ? BorderSide(color: st.fg.withValues(alpha: 0.5), width: 1.5)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(st.icon, color: st.fg, size: 24),
                    const SizedBox(height: 2),
                    Text(
                      s.statusShort(status),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: st.fg, fontWeight: FontWeight.w800, fontSize: 14.5),
                    ),
                    Text(
                      s.statusMeaning(status),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: st.fg.withValues(alpha: 0.8), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              if (selected) const Positioned(top: 6, right: 6, child: Icon(Icons.check_circle_rounded, size: 18)),
            ],
          ),
        ),
      ),
    );
  }
}
