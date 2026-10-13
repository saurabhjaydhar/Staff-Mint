import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/providers.dart';
import '../../../core/api/services/verification_api.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../documents/documents.dart';
import '../../profile/profile_screen.dart' show photoPickerProvider;

final myVerificationProvider = FutureProvider.autoDispose<MyVerification>(
  (ref) => ref.watch(verificationApiProvider).mine(),
);

/// The owner doing the steps with someone who has no smartphone.
final onBehalfVerificationProvider = FutureProvider.autoDispose.family<MyVerification, String>(
  (ref, employeeId) => ref.watch(verificationApiProvider).mine(employeeId: employeeId),
);

/// Staff: agree first (step 0), then Aadhaar with an OTP, PAN, the bank account with a ₹1 test, and a selfie.
/// With [employee]: the owner does the same steps with them (they agree on paper, with a signed slip).
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key, this.employee});
  final Employee? employee;

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _aadhaar = TextEditingController();
  final _otp = TextEditingController();
  final _pan = TextEditingController();
  final _account = TextEditingController();
  final _ifsc = TextEditingController();
  final _dl = TextEditingController();
  final _voter = TextEditingController();
  final _uan = TextEditingController();
  DateTime? _dob;
  bool _otherBank = false;
  bool _otherUan = false;
  bool _busy = false;
  bool _agreed = false;
  DocFile? _slip;
  MyVerification? _v;

  String? get _for => widget.employee?.id;
  bool get _owner => widget.employee != null;
  void _reload() =>
      _owner ? ref.invalidate(onBehalfVerificationProvider(_for!)) : ref.invalidate(myVerificationProvider);

  @override
  void dispose() {
    for (final c in [_aadhaar, _otp, _pan, _account, _ifsc, _dl, _voter, _uan]) {
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
    if (next != null) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final async = _owner ? ref.watch(onBehalfVerificationProvider(_for!)) : ref.watch(myVerificationProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_owner ? s.doingFor(widget.employee!.name) : s.verifyCardTitle)),
      body: AsyncBody<MyVerification>(
        value: _v != null ? AsyncData(_v!) : async,
        onRetry: _reload,
        data: (v) {
          if (v.request == null) return EmptyView(message: s.nothingHere);
          if (!v.request!.consented) return _owner ? _consentOnPaper(s, v) : _consent(s, v);
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

  /// Owner: read the same words to them, tick that they agreed, and add a photo of the slip they signed.
  Widget _consentOnPaper(S s, MyVerification v) {
    final name = widget.employee!.name;
    final lines = s.isHindi ? v.consentHi : v.consentEn;
    return ListView(
      key: const Key('verifyConsentPaper'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(s.readThisTo(name), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('• $l', style: const TextStyle(fontSize: 15.5, height: 1.35)),
          ),
        CheckboxListTile(
          key: const Key('verifyPaperAgreed'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _agreed,
          onChanged: (x) => setState(() => _agreed = x ?? false),
          title: Text(s.theyAgreedSigned(name), style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Text(s.slipPhotoNeeded, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          key: const Key('verifySlipPhoto'),
          onPressed: () async {
            final f = await ref.read(docPickerProvider).pick(ImageSource.camera);
            if (f != null) setState(() => _slip = f);
          },
          icon: Icon(_slip == null ? Icons.add_a_photo_rounded : Icons.check_circle_rounded),
          label: Text(_slip == null ? s.addSlipPhoto : s.slipAdded),
        ),
        const SizedBox(height: 14),
        FilledButton(
          key: const Key('verifyPaperGo'),
          onPressed: _busy || !_agreed || _slip == null ? null : () => _do((api) => api.consentOnPaper(_for!, _slip!)),
          child: Text(s.continueBtn),
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
      'mismatch' when kind == 'face' => s.staffFaceMismatch,
      'not_found' when kind == 'face' => s.staffFaceNoFace,
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

  /// After adding an ID photo: fetch the steps again (the selfie step needs it).
  Future<void> _reloadNow() async {
    final next = await ref.read(verificationApiProvider).mine(employeeId: _for);
    if (mounted) setState(() => _v = next);
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
              Text(
                _owner ? s.otpToTheirPhone(widget.employee!.name) : s.otpSentAadhaar,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('verifyOtp'),
                controller: _otp,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                decoration: InputDecoration(labelText: s.otpLabel),
              ),
              const SizedBox(height: 10),
              _go(
                'verifyOtpGo',
                s.verifyBtn,
                () => _do((api) => api.aadhaarVerify(_otp.text.trim(), employeeId: _for)),
              ),
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
            _go('verifySendOtp', s.sendOtp, () => _do((api) => api.aadhaarOtp(_aadhaar.text.trim(), employeeId: _for))),
          ],
        );
      case 'face':
        if (!v.idPhoto) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_owner ? s.faceNeedsIdOwner : s.faceNeedsId, style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 10),
              _go('verifyAddId', s.addIdPhoto, () async {
                if (await showAddDocumentSheet(context, employee: widget.employee)) await _reloadNow();
              }),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_owner ? s.faceTheirHint : s.faceSelfieHint, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 10),
            _go('verifySelfie', _owner ? s.takeTheirPhoto : s.takeSelfie, () async {
              final photo = await ref.read(photoPickerProvider).pick(ImageSource.camera);
              if (photo != null) await _do((api) => api.face(photo, employeeId: _for));
            }),
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
            _go('verifyPanGo', s.checkPan, () => _do((api) => api.pan(_pan.text.trim(), employeeId: _for))),
          ],
        );
      case 'dl':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('verifyDl'),
              controller: _dl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [LengthLimitingTextInputFormatter(20)],
              decoration: InputDecoration(labelText: s.dlLabel, hintText: 'DL04 2019 1234567'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('verifyDob'),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dob ?? DateTime(now.year - 25),
                  firstDate: DateTime(1940),
                  lastDate: DateTime(now.year - 14, now.month, now.day),
                  helpText: s.dobHintDl,
                );
                if (picked != null) setState(() => _dob = picked);
              },
              icon: const Icon(Icons.cake_rounded),
              label: Text(
                _dob == null
                    ? s.pickDob
                    : '${s.dobLabel}: ${Dates.prettyApiDate(Dates.toApiDate(_dob!), s.languageCode)}',
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('verifyDlGo'),
                onPressed: _busy || _dob == null
                    ? null
                    : () => _do((api) => api.dl(_dl.text.trim(), Dates.toApiDate(_dob!), employeeId: _for)),
                child: Text(s.checkDl),
              ),
            ),
          ],
        );
      case 'voter':
        return Column(
          children: [
            TextField(
              key: const Key('verifyVoter'),
              controller: _voter,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [LengthLimitingTextInputFormatter(12)],
              decoration: InputDecoration(labelText: s.voterLabel, hintText: 'ABC1234567'),
            ),
            const SizedBox(height: 10),
            _go('verifyVoterGo', s.checkVoter, () => _do((api) => api.voter(_voter.text.trim(), employeeId: _for))),
          ],
        );
      case 'uan':
        if (v.savedUanLast4 != null && !_otherUan) {
          return Column(
            children: [
              _go('verifyUanSaved', s.uanUseSaved(v.savedUanLast4!), () => _do((api) => api.uan(employeeId: _for))),
              TextButton(
                key: const Key('verifyUanOther'),
                onPressed: () => setState(() => _otherUan = true),
                child: Text(s.uanOther),
              ),
            ],
          );
        }
        return Column(
          children: [
            TextField(
              key: const Key('verifyUan'),
              controller: _uan,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
              decoration: InputDecoration(labelText: s.uanLabel, hintText: '100123456789'),
            ),
            const SizedBox(height: 10),
            _go('verifyUanGo', s.checkUan, () => _do((api) => api.uan(uan: _uan.text.trim(), employeeId: _for))),
          ],
        );
      default:
        if (v.savedBankLast4 != null && !_otherBank) {
          return Column(
            children: [
              _go(
                'verifyBankSaved',
                s.bankUseSaved(v.savedBankLast4!, v.savedBankIfsc ?? ''),
                () => _do((api) => api.bank(employeeId: _for)),
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
              () => _do(
                (api) => api.bank(accountNumber: _account.text.trim(), ifsc: _ifsc.text.trim(), employeeId: _for),
              ),
            ),
          ],
        );
    }
  }
}
