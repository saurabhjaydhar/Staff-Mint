import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/bilingual.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/receipt.dart';
import '../../auth/auth_controller.dart';

/// "PAID ✓" when the run is paid or the slip was sent, "APPROVED" once
/// approved, nothing for drafts.
String? payslipStamp(S s, Payslip p, {PayrollRun? run}) {
  if ((run?.isPaid ?? false) || p.status == 'sent') return s.stampPaid;
  if ((run?.isApproved ?? false) || p.status == 'final') return s.stampApproved;
  return null;
}

String _days(S s, Payslip p) => p.wageType == 'daily' ? s.daysOnly(p.payableDays) : s.daysOf(p.payableDays, p.divisor);

/// The payslip as a receipt: company · month, big net pay, earning (+) and
/// deduction (−) lines, a plain-language "why?" box and an optional stamp.
class PayslipReceipt extends ConsumerWidget {
  const PayslipReceipt({super.key, required this.payslip, this.stamp, this.anomalies = const []});
  final Payslip payslip;
  final String? stamp;
  final List<PayrollAnomaly> anomalies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final p = payslip;
    final company = ref.watch(authControllerProvider.select((v) => v.company?.name));
    final month = Dates.monthTitle(Dates.parseMonth(p.month), s.languageCode);
    return ReceiptCard(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text([?company, month].join(' · '), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              Text(s.netPayBi.joined, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 6),
              Text(
                Money.format(p.netPaise),
                key: const Key('payslipNet'),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, height: 1.05),
              ),
              Text(
                _days(s, p),
                style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
              if (p.paidOn != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    key: const Key('slipPaidOn'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      '✓ ${s.paidOnVia(Dates.prettyApiDate(p.paidOn!, s.languageCode), s.paymentMethodLabel(p.paymentMethod ?? 'cash'))}',
                      style: const TextStyle(color: AppColors.mintDark, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              for (final a in anomalies)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 18),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          a.message,
                          style: const TextStyle(color: AppColors.amberDark, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              // Deductions show only when there are some (no "−₹0").
              for (final l in p.lines)
                if (!(l.isDeduction && l.amountPaise == 0)) _line(l),
              if (p.employerContributions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  key: const Key('slipEmployer'),
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(s.employerOnTop, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      for (final c in p.employerContributions)
                        ReceiptRow(label: c.label, value: Money.format(c.amountPaise)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _WhyBox(payslip: p),
            ],
          ),
          if (stamp != null) Positioned(right: -4, top: 52, child: Stamp(text: stamp!)),
        ],
      ),
    );
  }

  Widget _line(PayslipLine l) {
    final amount = Money.format(l.amountPaise.abs());
    if (l.isDeduction) return ReceiptRow(label: l.label, value: '− $amount', valueColor: AppColors.red);
    if (l.code == 'basic' || l.code == 'allowance') return ReceiptRow(label: l.label, value: amount);
    return ReceiptRow(label: l.label, value: '+ $amount', valueColor: AppColors.mint);
  }
}

/// "क्यों? …" from `/payslips/:id/explain`; estimates explain from their lines.
class _WhyBox extends ConsumerStatefulWidget {
  const _WhyBox({required this.payslip});
  final Payslip payslip;

  @override
  ConsumerState<_WhyBox> createState() => _WhyBoxState();
}

class _WhyBoxState extends ConsumerState<_WhyBox> {
  late final Future<PayslipExplanation>? _explain = widget.payslip.isPersisted
      ? ref.read(payrollApiProvider).explain(widget.payslip.id)
      : null;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final payslip = widget.payslip;
    Widget box(String text) => Container(
      key: const Key('whyBox'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AppColors.whyBg, borderRadius: BorderRadius.circular(10)),
      child: Text('${s.why} $text', style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.4)),
    );
    final local = payslip.lines.map((l) => l.explanation).where((e) => e.isNotEmpty).join(' · ');
    if (_explain == null) return local.isEmpty ? const SizedBox.shrink() : box(local);
    return FutureBuilder<PayslipExplanation>(
      future: _explain,
      builder: (_, snap) {
        final e = snap.data;
        if (e == null) return local.isEmpty ? const SizedBox.shrink() : box(local);
        return box([e.text, ...e.lines].where((t) => t.isNotEmpty).join('\n'));
      },
    );
  }
}

/// Compact payslip line for lists: name · days · net → opens the receipt.
class PayslipTile extends StatelessWidget {
  const PayslipTile({super.key, required this.payslip, required this.onTap, this.title});
  final Payslip payslip;
  final VoidCallback onTap;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = payslip;
    return ListTile(
      onTap: onTap,
      leading: InitialsAvatar(p.employeeName, radius: 18),
      title: Text(title ?? p.employeeName),
      subtitle: Text(_days(s, p)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(Money.format(p.netPaise), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    );
  }
}

/// Opens the full payslip receipt with WhatsApp + PDF actions.
Future<void> openPayslipDetail(
  BuildContext context,
  Payslip payslip, {
  String? stamp,
  bool ownerView = false,
  List<PayrollAnomaly> anomalies = const [],
  Future<void> Function()? onEdit,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) =>
        PayslipDetailScreen(payslip: payslip, stamp: stamp, ownerView: ownerView, anomalies: anomalies, onEdit: onEdit),
  ),
);

class PayslipDetailScreen extends ConsumerStatefulWidget {
  const PayslipDetailScreen({
    super.key,
    required this.payslip,
    this.stamp,
    this.ownerView = false,
    this.anomalies = const [],
    this.onEdit,
  });
  final Payslip payslip;
  final String? stamp;
  final bool ownerView;
  final List<PayrollAnomaly> anomalies;

  /// Owner, draft run: add a bonus / deduction for this person.
  final Future<void> Function()? onEdit;

  @override
  ConsumerState<PayslipDetailScreen> createState() => _PayslipDetailScreenState();
}

class _PayslipDetailScreenState extends ConsumerState<PayslipDetailScreen> {
  bool _busy = false;

  bool get _final => widget.payslip.isPersisted && widget.payslip.status != 'draft';

  Future<void> _whatsApp() async {
    final s = context.s;
    final p = widget.payslip;
    setState(() => _busy = true);
    String? url;
    String? phone;
    try {
      url = (await ref.read(payrollApiProvider).payslip(p.id)).pdfUrl ?? p.pdfUrl;
    } catch (_) {
      url = p.pdfUrl;
    }
    if (widget.ownerView) {
      try {
        phone = (await ref.read(employeesApiProvider).get(p.employeeId)).phone;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final digits = phone == null ? null : Phones.waDigits(phone);
    final firstName = p.employeeName.trim().split(RegExp(r'\s+')).first;
    final text = s.waPayslipMessage(
      firstName,
      Dates.monthTitle(Dates.parseMonth(p.month), s.languageCode),
      Money.format(p.netPaise),
      url,
    );
    await openUrl(context, 'https://wa.me/${digits ?? ''}?text=${Uri.encodeComponent(text)}');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = widget.payslip;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.payslipBi.joined, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            Text(p.employeeName, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        actions: const [LangPill(), SizedBox(width: 8)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          PayslipReceipt(payslip: p, stamp: widget.stamp, anomalies: widget.anomalies),
          if (widget.onEdit != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('payslipEdit'),
              onPressed: widget.onEdit,
              icon: const Icon(Icons.edit_rounded),
              label: Text(s.addAdjustment),
            ),
          ],
          if (!_final) ...[
            const SizedBox(height: 12),
            Text(
              s.pdfAfterApproval,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ],
      ),
      bottomNavigationBar: !_final
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        key: const Key('payslipWhatsApp'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.whatsapp,
                          minimumSize: const Size(48, 54),
                        ),
                        onPressed: _busy ? null : _whatsApp,
                        icon: const Icon(Icons.chat_rounded),
                        label: Text(s.sendOnWhatsApp, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 54),
                          side: const BorderSide(color: AppColors.ink, width: 2),
                        ),
                        onPressed: () => openPayslipPdf(context, ref, p),
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: Text(s.pdf),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// `GET /payslips/:id` returns a fresh short-lived signed `pdfUrl`.
Future<void> openPayslipPdf(BuildContext context, WidgetRef ref, Payslip p) async {
  try {
    final fresh = await ref.read(payrollApiProvider).payslip(p.id);
    final url = fresh.pdfUrl ?? p.pdfUrl;
    if (!context.mounted) return;
    if (url == null) {
      showSnack(context, context.s.couldNotOpen, error: true);
      return;
    }
    await openUrl(context, url);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
