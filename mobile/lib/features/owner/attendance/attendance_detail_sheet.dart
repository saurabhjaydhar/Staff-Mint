import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../providers/owner_providers.dart';

const overrideStatuses = ['present', 'absent', 'half_day', 'leave', 'holiday', 'week_off'];

Future<void> showAttendanceDetail(BuildContext context, {required DayRow row, required String date}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, controller) => AttendanceDetailSheet(row: row, date: date, controller: controller),
      ),
    ),
  );
}

/// Punches (selfie, location, distance, flags) + override with reason.
class AttendanceDetailSheet extends ConsumerStatefulWidget {
  const AttendanceDetailSheet({super.key, required this.row, required this.date, this.controller});
  final DayRow row;
  final String date;
  final ScrollController? controller;

  @override
  ConsumerState<AttendanceDetailSheet> createState() => _AttendanceDetailSheetState();
}

class _AttendanceDetailSheetState extends ConsumerState<AttendanceDetailSheet> {
  late String _status = _initialStatus();
  String _leaveType = 'paid';
  final _reason = TextEditingController();
  bool _busy = false;
  late Attendance? _record = widget.row.record;

  String _initialStatus() {
    final st = widget.row.record?.status;
    if (st != null && overrideStatuses.contains(st)) return st;
    return 'present';
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.s;
    if (_reason.text.trim().isEmpty) {
      showSnack(context, s.reasonRequired, error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await runGuarded(context, () async {
      await ref
          .read(attendanceApiProvider)
          .overrideStatus(
            employeeId: widget.row.employee.id,
            date: widget.date,
            status: _status,
            leaveType: _status == 'leave' ? _leaveType : null,
            reason: _reason.text.trim(),
          );
    }, success: s.attendanceUpdated);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      invalidateAttendance(ref);
      Navigator.pop(context);
    }
  }

  Future<void> _decide(Punch p, bool approve) async {
    final rec = _record;
    if (rec == null) return;
    final s = context.s;
    try {
      final updated = await ref.read(attendanceApiProvider).decidePunch(rec.id, p.id, approve);
      if (!mounted) return;
      setState(() => _record = updated);
      invalidateAttendance(ref);
      showSnack(context, approve ? s.approved : s.rejected);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final rec = _record;
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(
          children: [
            InitialsAvatar(widget.row.employee.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.row.employee.name, style: Theme.of(context).textTheme.titleLarge),
                  Text(Dates.prettyApiDate(widget.date, s.languageCode)),
                ],
              ),
            ),
            StatusChip(status: widget.row.displayStatus),
          ],
        ),
        if (rec != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (rec.lateMinutes > 0) Text(s.lateBy(rec.lateMinutes), style: const TextStyle(color: AppColors.late)),
              if (rec.earlyOutMinutes > 0) Text(s.earlyOutBy(rec.earlyOutMinutes)),
              if (rec.workedMinutes > 0) Text(s.worked(Dates.durationHm(rec.workedMinutes))),
            ],
          ),
          if (rec.overridden && rec.overrideReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${s.overriddenTag}: ${rec.overrideReason}',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          const SizedBox(height: 8),
          FlagChips(flags: rec.flags),
        ],
        const SizedBox(height: 16),
        Text(s.punches, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (rec == null || rec.punches.isEmpty)
          Text(s.noPunches, style: const TextStyle(color: Colors.black54))
        else
          for (final p in rec.punches) _PunchCard(punch: p, onDecide: (a) => _decide(p, a)),
        const Divider(height: 32),
        Text(s.changeStatus, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final st in overrideStatuses)
              ChoiceChip(
                label: Text(s.statusLabel(st)),
                selected: _status == st,
                selectedColor: AppColors.forStatus(st).withValues(alpha: 0.25),
                onSelected: (_) => setState(() => _status = st),
              ),
          ],
        ),
        if (_status == 'leave') ...[
          const SizedBox(height: 12),
          Text(s.leaveTypeTitle),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              for (final t in const ['paid', 'sick', 'unpaid'])
                ButtonSegment(
                  value: t,
                  label: Text(s.leaveTypeLabel(t), style: const TextStyle(fontSize: 13)),
                ),
            ],
            selected: {_leaveType},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _leaveType = v.first),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _reason,
          decoration: InputDecoration(labelText: s.reason, hintText: s.overrideReasonHint),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _save, child: Text(s.save)),
      ],
    );
  }
}

class _PunchCard extends StatelessWidget {
  const _PunchCard({required this.punch, required this.onDecide});
  final Punch punch;
  final ValueChanged<bool> onDecide;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = punch;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: p.selfieUrl == null
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(p.selfieUrl!))),
                        ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: p.selfieUrl == null
                        ? Container(
                            width: 72,
                            height: 72,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.no_photography_outlined),
                          )
                        : Image.network(
                            p.selfieUrl!,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 72,
                              height: 72,
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p.isIn ? s.checkInLabel : s.checkOutLabel} · ${Dates.time(p.clientTime, s.languageCode)}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      if (p.geo != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (p.insideGeofence != null) p.insideGeofence! ? s.insideArea : s.outsideArea,
                            if (p.distanceM != null) s.distanceAway(p.distanceM!),
                            if (p.geo!.accuracyM != null) s.accuracy(p.geo!.accuracyM!),
                          ].join(' · '),
                          style: TextStyle(color: p.insideGeofence == false ? AppColors.absent : Colors.black54),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                          onPressed: () => openUrl(
                            context,
                            'https://www.openstreetmap.org/?mlat=${p.geo!.lat}&mlon=${p.geo!.lng}#map=18/${p.geo!.lat}/${p.geo!.lng}',
                          ),
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: Text(s.openMap),
                        ),
                      ],
                      if (p.approval != 'not_required')
                        Text(
                          s.approvalLabel(p.approval),
                          style: TextStyle(
                            color: p.isPendingApproval ? AppColors.late : Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (p.flags.isNotEmpty) ...[const SizedBox(height: 8), FlagChips(flags: p.flags)],
            if (p.isPendingApproval) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.absent),
                      onPressed: () => onDecide(false),
                      child: Text(s.reject),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(onPressed: () => onDecide(true), child: Text(s.approve)),
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
