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

/// Light "2 things need your OK" card that says what each request is, and
/// expands into the actionable list: leave requests (with the effect of
/// saying yes), check-ins away from the shop, face photos and new phones.
class NeedsYouCard extends ConsumerStatefulWidget {
  const NeedsYouCard({super.key, required this.dashboard, this.notJoined = 0, this.onRemindAll});
  final Dashboard dashboard;

  /// Staff who haven't installed the app yet; shown as one more "To do" item.
  final int notJoined;
  final VoidCallback? onRemindAll;

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

  Future<bool> _decideLeave(Leave l, bool approve, {bool asUnpaid = false}) =>
      _run(l.id, approve, () => ref.read(leaveApiProvider).decide(l.id, approve: approve, asUnpaid: asUnpaid));

  Future<bool> _decideFace(FaceEnrollment f, bool approve) => _run(
    'face_${f.employeeId}',
    approve,
    () => approve
        ? ref.read(employeesApiProvider).approveFace(f.employeeId)
        : ref.read(employeesApiProvider).resetFace(f.employeeId),
  );

  Future<bool> _decideDevice(DeviceRequestItem r, bool approve) =>
      _run('device_${r.id}', approve, () => ref.read(accountsApiProvider).decideDevice(r.id, approve: approve));

  Future<bool> _decidePunch(PunchApprovalItem p, bool approve) =>
      _run(p.punch.id, approve, () => ref.read(attendanceApiProvider).decidePunch(p.attendanceId, p.punch.id, approve));

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = widget.dashboard;
    final leaves = d.leaveRequests.where((l) => !_handled.contains(l.id)).toList();
    final punches = d.punchApprovals.where((p) => !_handled.contains(p.punch.id)).toList();
    final faces = d.faceEnrollments.where((f) => !_handled.contains('face_${f.employeeId}')).toList();
    final devices = d.deviceRequests.where((r) => !_handled.contains('device_${r.id}')).toList();
    final approvals = leaves.length + punches.length + faces.length + devices.length + d.flags.length;
    final invites = widget.notJoined > 0 ? 1 : 0;
    final count = approvals + invites;
    if (count == 0) return const SizedBox.shrink();
    final names = [
      for (final l in leaves) s.okAskedLeave(l.employeeName),
      for (final p in punches) _punchTitle(s, p),
      if (widget.notJoined > 0) s.todoNotJoined(widget.notJoined),
      for (final f in faces) s.needsYouFace(f.employeeName),
      for (final r in devices) s.needsYouDevice(r.employeeName),
      for (final f in d.flags) s.okCheck(f.employeeName),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('needsYouCard'),
          margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          decoration: BoxDecoration(
            color: AppColors.amberLight,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.amberDark.withValues(alpha: 0.25)),
          ),
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
                          s.todoCount(count),
                          style: const TextStyle(color: AppColors.ink, fontSize: 15.5, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          names.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted, fontSize: 13),
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
                          _open ? s.hide : s.openScreen,
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
                          onApproveUnpaid: () async {
                            if (await _decideLeave(l, true, asUnpaid: true) && mounted) {
                              setState(() => _handled.add(l.id));
                            }
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
                    for (final f in faces)
                      _FaceEnrollmentCard(
                        item: f,
                        busy: _busy.contains('face_${f.employeeId}'),
                        onDecide: (a) async {
                          if (await _decideFace(f, a) && mounted) setState(() => _handled.add('face_${f.employeeId}'));
                        },
                      ),
                    for (final r in devices)
                      Card(
                        key: Key('deviceRequest_${r.id}'),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const CircleAvatar(
                                    backgroundColor: AppColors.indigoLight,
                                    child: Icon(Icons.phonelink_setup_rounded, color: AppColors.indigo),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(r.employeeName, style: Theme.of(context).textTheme.titleMedium),
                                        Text(
                                          s.deviceRequestBody(r.deviceName),
                                          style: const TextStyle(color: AppColors.muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              DecisionButtons(
                                busy: _busy.contains('device_${r.id}'),
                                onDecide: (a) async {
                                  if (await _decideDevice(r, a) && mounted) {
                                    setState(() => _handled.add('device_${r.id}'));
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (widget.notJoined > 0)
                      Card(
                        key: const Key('todoInvites'),
                        child: ListTile(
                          leading: const Icon(Icons.mark_email_unread_outlined, color: AppColors.amberDark),
                          title: Text(s.todoInviteLine(widget.notJoined)),
                          trailing: TextButton(onPressed: widget.onRemindAll, child: Text(s.remindAll)),
                        ),
                      ),
                    if (leaves.isNotEmpty || punches.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: Text(s.swipeTip, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
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
                      Text(_punchTitle(s, item), style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        s.todayAt(Dates.time(p.clientTime, s.languageCode)),
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (p.faceFlagged && item.facePhotoUrl != null) ...[
              const SizedBox(height: 10),
              PhotoPair(
                key: Key('photoPair_${p.id}'),
                left: (s.approvedPhoto, item.facePhotoUrl),
                right: (s.todaysSelfie, p.selfieUrl),
              ),
            ],
            const SizedBox(height: 10),
            DecisionButtons(
              busy: busy,
              onDecide: onDecide,
              rejectLabel: s.dontCount,
              approveLabel: p.faceFlagged && !outside ? s.itsThem : s.countAsPresent,
            ),
          ],
        ),
      ),
    );
  }
}

/// A face photo a staff member just set up: approve, or ask for a new one.
class _FaceEnrollmentCard extends StatelessWidget {
  const _FaceEnrollmentCard({required this.item, required this.busy, required this.onDecide});
  final FaceEnrollment item;
  final bool busy;
  final ValueChanged<bool> onDecide;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Card(
      key: Key('faceEnrollment_${item.employeeId}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Photo(url: item.face.photoUrl, size: 72),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.employeeName, style: Theme.of(context).textTheme.titleMedium),
                      Text(s.facePhotoToApprove, style: const TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DecisionButtons(busy: busy, onDecide: onDecide, rejectLabel: s.faceAskRetake),
          ],
        ),
      ),
    );
  }
}

/// Approved face photo next to today's selfie, so the owner can compare by eye.
class PhotoPair extends StatelessWidget {
  const PhotoPair({super.key, required this.left, required this.right});
  final (String, String?) left;
  final (String, String?) right;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (label, url) in [left, right])
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                AspectRatio(aspectRatio: 1, child: _Photo(url: url)),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
          ),
        ),
    ],
  );
}

class _Photo extends StatelessWidget {
  const _Photo({required this.url, this.size});
  final String? url;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: AppColors.mutedLight,
      child: const Icon(Icons.person, color: AppColors.muted),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: url == null
          ? fallback
          : Image.network(url!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
}

/// One plain sentence for a check-in that needs the owner: away from the
/// shop, selfie looks different, or the phone wasn't unlocked.
String _punchTitle(S s, PunchApprovalItem item) {
  final p = item.punch;
  if (p.insideGeofence == false && p.distanceM != null) {
    return s.checkedInAway(item.employeeName, s.rowAway(p.distanceM!));
  }
  if (p.mockLocation || p.insideGeofence == false) return s.okFarPunch(item.employeeName);
  if (p.faceFlagged) return s.selfieDifferent(item.employeeName);
  return s.noPhoneLock(item.employeeName);
}
