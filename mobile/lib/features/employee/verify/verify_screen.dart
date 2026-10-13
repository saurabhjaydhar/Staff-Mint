import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/api/services/verification_api.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';

final myVerificationProvider = FutureProvider.autoDispose<MyVerification>(
  (ref) => ref.watch(verificationApiProvider).mine(),
);

/// Staff: agree first (step 0), then Aadhaar with an OTP, PAN, and the bank account with a ₹1 test.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _aadhaar = TextEditingController();
  final _otp = TextEditingController();
  final _pan = TextEditingController();
  final _account = TextEditingController();
  final _ifsc = TextEditingController();
  bool _otherBank = false;
  bool _busy = false;
  MyVerification? _v;

  @override
  void dispose() {
    for (final c in [_aadhaar, _otp, _pan, _account, _ifsc]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _do(Future<MyVerification> Function(VerificationApi api) call) async {
    setState(() => _busy = true);
    MyVerification? next;
    await runGuarded(context, () async => next = await call(ref.read(verificationApiProvider)));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (next != null) _v = next;
    });
    if (next != null) ref.invalidate(myVerificationProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final async = ref.watch(myVerificationProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.verifyCardTitle)),
      body: AsyncBody<MyVerification>(
        value: _v != null ? AsyncData(_v!) : async,
        onRetry: () => ref.invalidate(myVerificationProvider),
        data: (v) {
          if (v.request == null) return EmptyView(message: s.nothingHere);
          if (!v.request!.consented) return _consent(s, v);
          return _steps(s, v);
        },
      ),
    );
  }

  Widget _consent(S s, MyVerification v) {
    final lines = s.isHindi ? v.consentHi : v.consentEn;
    return ListView(
      key: const Key('verifyConsent'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(s.verifyConsentTitle, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(s.verifyCardHint(v.businessName), style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 14),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_circle_outline_rounded, color: AppColors.mintDark, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(l, style: const TextStyle(fontSize: 15.5, height: 1.35))),
              ],
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('verifyAllow'),
          onPressed: _busy ? null : () => _do((api) => api.consent()),
          child: Text(s.allowStart),
        ),
      ],
    );
  }

  Widget _steps(S s, MyVerification v) {
    final kinds = v.request!.kinds;
    // The step to do now: the first one that isn't fine and isn't waiting for the owner to look at a name.
    final current = kinds.where((k) {
      final c = v.check(k);
      return c != null && !c.ok && c.status != 'mismatch';
    }).firstOrNull;
    return ListView(
      key: const Key('verifySteps'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final (i, k) in kinds.indexed) _stepCard(s, v, k, i + 1, kinds.length, k == current),
        if (current == null)
          Container(
            key: const Key('verifyAllDone'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Icon(Icons.celebration_rounded, color: AppColors.mintDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(s.allDone, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _stepCard(S s, MyVerification v, String kind, int n, int total, bool open) {
    final c = v.check(kind)!;
    final (icon, color) = c.ok
        ? (Icons.check_circle_rounded, AppColors.mint)
        : c.status == 'mismatch'
        ? (Icons.hourglass_top_rounded, AppColors.amber)
        : (Icons.radio_button_unchecked_rounded, open ? AppColors.ink : AppColors.line);
    final note = switch (c.status) {
      'mismatch' => s.staffMismatch(c.nameOnRecord ?? ''),
      'not_found' => s.staffNotFound,
      'failed' => s.staffFailed,
      _ => null,
    };
    return Card(
      key: Key('verifyStep_$kind'),
      color: open ? Colors.white : null,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.stepOf(n, total), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      Text(s.docKind(kind), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    ],
                  ),
                ),
                if (c.ok)
                  Text(
                    s.resVerified,
                    style: const TextStyle(color: AppColors.mintDark, fontWeight: FontWeight.w800),
                  ),
              ],
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  note,
                  style: const TextStyle(color: AppColors.amberDark, fontWeight: FontWeight.w600),
                ),
              ),
            if (open) ...[const SizedBox(height: 10), _form(s, v, c)],
          ],
        ),
      ),
    );
  }

  Widget _go(String key, String label, VoidCallback onPressed) => SizedBox(
    width: double.infinity,
    child: FilledButton(key: Key(key), onPressed: _busy ? null : onPressed, child: Text(label)),
  );

  Widget _form(S s, MyVerification v, VerifyCheck c) {
    switch (c.kind) {
      case 'aadhaar':
        if (c.status == 'otp_sent') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.otpSentAadhaar, style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 6),
              TextField(
                key: const Key('verifyOtp'),
                controller: _otp,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                decoration: InputDecoration(labelText: s.otpLabel),
              ),
              const SizedBox(height: 10),
              _go('verifyOtpGo', s.verifyBtn, () => _do((api) => api.aadhaarVerify(_otp.text.trim()))),
            ],
          );
        }
        return Column(
          children: [
            TextField(
              key: const Key('verifyAadhaar'),
              controller: _aadhaar,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
              decoration: InputDecoration(labelText: s.aadhaarLabel, hintText: '1234 5678 9012'),
            ),
            const SizedBox(height: 10),
            _go('verifySendOtp', s.sendOtp, () => _do((api) => api.aadhaarOtp(_aadhaar.text.trim()))),
          ],
        );
      case 'pan':
        return Column(
          children: [
            TextField(
              key: const Key('verifyPan'),
              controller: _pan,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [LengthLimitingTextInputFormatter(10)],
              decoration: InputDecoration(labelText: s.panLabel, hintText: 'ABCDE1234F'),
            ),
            const SizedBox(height: 10),
            _go('verifyPanGo', s.checkPan, () => _do((api) => api.pan(_pan.text.trim()))),
          ],
        );
      default:
        if (v.savedBankLast4 != null && !_otherBank) {
          return Column(
            children: [
              _go(
                'verifyBankSaved',
                s.bankUseSaved(v.savedBankLast4!, v.savedBankIfsc ?? ''),
                () => _do((api) => api.bank()),
              ),
              TextButton(
                key: const Key('verifyBankOther'),
                onPressed: () => setState(() => _otherBank = true),
                child: Text(s.bankOther),
              ),
            ],
          );
        }
        return Column(
          children: [
            TextField(
              key: const Key('verifyAccount'),
              controller: _account,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)],
              decoration: InputDecoration(labelText: s.accountLabel),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('verifyIfsc'),
              controller: _ifsc,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [LengthLimitingTextInputFormatter(11)],
              decoration: InputDecoration(labelText: s.ifscLabel, hintText: 'SBIN0001234'),
            ),
            const SizedBox(height: 10),
            _go(
              'verifyBankGo',
              s.checkBank,
              () => _do((api) => api.bank(accountNumber: _account.text.trim(), ifsc: _ifsc.text.trim())),
            ),
          ],
        );
    }
  }
}
