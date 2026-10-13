import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../employee/verify/verify_screen.dart';
import '../providers/owner_providers.dart';

const verifyKinds = ['aadhaar', 'pan', 'dl', 'voter', 'bank', 'uan', 'face'];

/// Ticked to begin with; the rest are under "More checks".
const _mainKinds = ['aadhaar', 'pan', 'bank', 'face'];
const _moreKinds = ['dl', 'voter', 'uan'];

final ownerVerificationProvider = FutureProvider.autoDispose.family<OwnerVerification, String>(
  (ref, employeeId) => ref.watch(verificationApiProvider).forEmployee(employeeId),
);

/// Staff profile (owner only): is this person's Aadhaar, PAN and bank checked? "Check now", and the results.
class VerifyCard extends ConsumerWidget {
  const VerifyCard({super.key, required this.employee});
  final Employee employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final v = ref.watch(ownerVerificationProvider(employee.id)).value;
    if (v == null) return const SizedBox.shrink();
    final r = v.request;

    Future<void> run(Future<OwnerVerification> Function() call, [String? done]) async {
      final ok = await runGuarded(context, call);
      if (!ok || !context.mounted) return;
      ref.invalidate(ownerVerificationProvider(employee.id));
      ref.invalidate(employeesProvider);
      if (done != null) showSnack(context, done);
    }

    Future<void> accept(VerifyCheck c) async {
      final reason = await _askReason(context);
      if (reason == null || !context.mounted) return;
      await run(() => ref.read(verificationApiProvider).accept(c.id, reason));
    }

    final badge = switch (v.badge) {
      'verified' => (s.docVerified, AppColors.mintDark, AppColors.mintLight),
      'needs_attention' => (s.docNeedsLook, AppColors.amberDark, AppColors.amberLight),
      _ => null,
    };
    return Card(
      key: const Key('verifyCard'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: AppColors.mintDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(s.docCheckTitle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                if (badge != null)
                  Container(
                    key: const Key('verifyBadge'),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: badge.$3, borderRadius: BorderRadius.circular(99)),
                    child: Text(
                      badge.$1,
                      style: TextStyle(color: badge.$2, fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                  ),
              ],
            ),
            if (r == null) ...[
              const SizedBox(height: 4),
              Text(s.docCheckNone, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(s.docCheckNoneHint, style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('verifyCheckNow'),
                onPressed: () => _openCheckSheet(context, ref, employee, v),
                icon: const Icon(Icons.fact_check_rounded),
                label: Text(s.checkNow),
              ),
            ] else ...[
              if (r.status == 'asked')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(s.docAsked(employee.name), style: const TextStyle(color: AppColors.muted)),
                ),
              if (r.status == 'in_progress')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(s.docInProgress(employee.name), style: const TextStyle(color: AppColors.muted)),
                ),
              if (r.onPaper)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.draw_rounded, size: 18, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Text(s.agreedOnPaper, style: const TextStyle(color: AppColors.muted)),
                      if (r.hasSlip)
                        TextButton(
                          key: const Key('verifySeeSlip'),
                          onPressed: () => _showSlip(context, ref, employee),
                          child: Text(s.seeSlip),
                        ),
                    ],
                  ),
                ),
              for (final c in v.checks)
                _CheckRow(
                  check: c,
                  onAccept: () => accept(c),
                  onAskAgain: () => run(() => ref.read(verificationApiProvider).askAgain(c.id), s.askedAgain),
                ),
              if (r.open && !v.hasApp)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.doWithThemHint, style: const TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 6),
                      FilledButton.icon(
                        key: const Key('verifyDoWithThem'),
                        onPressed: () async {
                          await Navigator.of(
                            context,
                            rootNavigator: true,
                          ).push(MaterialPageRoute<void>(builder: (_) => VerifyScreen(employee: employee)));
                          ref.invalidate(ownerVerificationProvider(employee.id));
                          ref.invalidate(employeesProvider);
                        },
                        icon: const Icon(Icons.handshake_rounded),
                        label: Text(s.doWithThem),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  if (r.consented)
                    TextButton.icon(
                      key: const Key('verifyReport'),
                      onPressed: () async {
                        String? url;
                        final ok = await runGuarded(
                          context,
                          () async => url = await ref.read(verificationApiProvider).reportUrl(employee.id),
                        );
                        if (ok && url != null && context.mounted) await openUrl(context, url!);
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: Text(s.reportPdf),
                    ),
                  const Spacer(),
                  if (r.open)
                    TextButton(
                      key: const Key('verifyCancel'),
                      onPressed: () => run(() => ref.read(verificationApiProvider).cancel(employee.id)),
                      child: Text(s.cancelCheck),
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

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check, required this.onAccept, required this.onAskAgain});
  final VerifyCheck check;
  final VoidCallback onAccept;
  final VoidCallback onAskAgain;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final c = check;
    final (icon, color) = c.ok
        ? (Icons.check_circle_rounded, AppColors.mint)
        : c.needsLook
        ? (Icons.error_rounded, AppColors.amber)
        : c.status == 'failed'
        ? (Icons.refresh_rounded, AppColors.muted)
        : (Icons.radio_button_unchecked_rounded, AppColors.line);
    final lines = <String>[
      switch (c.status) {
        'verified' when c.kind == 'face' => s.resVerified,
        'mismatch' when c.kind == 'face' && !c.accepted => s.resMismatchFace,
        'not_found' when c.kind == 'face' => s.faceNoFaceOnId,
        'verified' => [s.resVerified, ?c.nameOnRecord].join(' · '),
        'mismatch' => c.accepted ? s.resAccepted(c.overrideReason!) : s.resMismatch(c.nameOnRecord ?? '—'),
        'not_found' => s.resNotFound,
        'failed' => s.resFailed,
        'otp_sent' => s.resOtpSent,
        _ => s.resWaiting,
      },
      if (c.accepted && c.nameOnRecord != null) s.resMismatch(c.nameOnRecord!),
      if (c.kind == 'face' && c.matchScore != null) s.faceMatch(c.matchScore!),
      if (c.kind == 'face' && c.details['idKind'] != null) s.faceWithId(s.fileKind(c.details['idKind']!)),
      if (c.last4 != null && c.status != 'waiting') s.endingIn(c.last4!),
      if (c.details['dob'] != null) s.docBorn(_dob(c.details['dob']!, s.languageCode)),
      if (c.details['validTill'] != null) s.validTillDate(_dob(c.details['validTill']!, s.languageCode)),
    ];
    String day(String? d) => d == null ? '?' : _dob(d, s.languageCode);
    return Padding(
      key: Key('verifyRow_${c.kind}'),
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.docKind(c.kind), style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(lines.join(' · '), style: TextStyle(color: c.needsLook ? AppColors.amberDark : AppColors.muted)),
                if (c.employers.isNotEmpty)
                  Padding(
                    key: Key('verifyJobs_${c.kind}'),
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.pastJobs, style: const TextStyle(fontWeight: FontWeight.w700)),
                        for (final j in c.employers)
                          Text(
                            '• ${j.name} · ${day(j.joined)} – ${j.left == null ? s.jobNow : day(j.left)}',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                      ],
                    ),
                  ),
                if (c.needsLook || c.status == 'failed')
                  Wrap(
                    spacing: 8,
                    children: [
                      if (c.status == 'mismatch')
                        FilledButton.tonal(
                          key: Key('verifyAccept_${c.kind}'),
                          onPressed: onAccept,
                          child: Text(s.thisIsFine),
                        ),
                      TextButton(key: Key('verifyAgain_${c.kind}'), onPressed: onAskAgain, child: Text(s.askAgainBtn)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showSlip(BuildContext context, WidgetRef ref, Employee e) async {
  String? url;
  final ok = await runGuarded(context, () async => url = await ref.read(verificationApiProvider).slipUrl(e.id));
  if (!ok || url == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.s.signedSlip),
      content: Image.network(url!, errorBuilder: (_, _, _) => Text(ctx.s.couldNotLoadFile)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.s.close))],
    ),
  );
}

/// "1995-04-12" or "12-04-1995" (as Aadhaar records come) → "12 Apr 1995".
String _dob(String raw, String lang) {
  final dmy = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(raw);
  final iso = dmy == null ? raw : '${dmy[3]}-${dmy[2]}-${dmy[1]}';
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(iso) ? Dates.prettyApiDate(iso, lang) : raw;
}

Future<String?> _askReason(BuildContext context) {
  final s = context.s;
  final ctl = TextEditingController(text: s.acceptDefault);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.acceptTitle),
      content: TextField(key: const Key('verifyReason'), controller: ctl, maxLength: 200, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
        FilledButton(
          key: const Key('verifyReasonSave'),
          onPressed: () => Navigator.pop(ctx, ctl.text.trim().isEmpty ? s.acceptDefault : ctl.text.trim()),
          child: Text(s.thisIsFine),
        ),
      ],
    ),
  );
}

Future<void> _openCheckSheet(BuildContext context, WidgetRef ref, Employee e, OwnerVerification v) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.paper,
    builder: (_) => _CheckSheet(employee: e, view: v),
  );
  if (sent == true && context.mounted) {
    ref.invalidate(ownerVerificationProvider(e.id));
    ref.invalidate(employeesProvider);
    showSnack(context, context.s.docSent(e.name));
  }
}

/// Pick what to check (all ticked), see what's left in the plan this month, send.
class _CheckSheet extends ConsumerStatefulWidget {
  const _CheckSheet({required this.employee, required this.view});
  final Employee employee;
  final OwnerVerification view;

  @override
  ConsumerState<_CheckSheet> createState() => _CheckSheetState();
}

class _CheckSheetState extends ConsumerState<_CheckSheet> {
  final _kinds = {..._mainKinds};
  bool _busy = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    final ok = await runGuarded(
      context,
      () => ref.read(verificationApiProvider).request(widget.employee.id, [
        for (final k in verifyKinds)
          if (_kinds.contains(k)) k,
      ]),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  Widget _kind(S s, String k) => CheckboxListTile(
    key: Key('verifyKind_$k'),
    contentPadding: EdgeInsets.zero,
    value: _kinds.contains(k),
    onChanged: (on) => setState(() => on == true ? _kinds.add(k) : _kinds.remove(k)),
    title: Text(s.docKind(k), style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(s.docKindHint(k)),
  );

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final v = widget.view;
    final noPlan = v.limit == 0;
    return SingleChildScrollView(
      key: const Key('verifySheet'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.checkSheetTitle(widget.employee.name),
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          Text(s.checkSheetHint, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          for (final k in _mainKinds) _kind(s, k),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              s.moreChecks,
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.muted),
            ),
          ),
          for (final k in _moreKinds) _kind(s, k),
          const SizedBox(height: 6),
          Container(
            key: const Key('verifyQuota'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: noPlan || v.left == 0 ? AppColors.amberLight : AppColors.mintFaint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              noPlan
                  ? s.checkNeedsPlan
                  : v.left == 0
                  ? s.checksUsedUp(v.limit, Money.format(v.extraPricePaise))
                  : s.checksLeft(v.left, v.limit),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: noPlan
                ? FilledButton(
                    key: const Key('verifySeePlans'),
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(context.push(Routes.ownerBilling));
                    },
                    child: Text(s.seePlans),
                  )
                : FilledButton(
                    key: const Key('verifySend'),
                    onPressed: _busy || v.left == 0 || _kinds.isEmpty ? null : _send,
                    child: Text(s.sendToPerson(widget.employee.name)),
                  ),
          ),
        ],
      ),
    );
  }
}
