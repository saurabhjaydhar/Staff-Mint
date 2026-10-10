import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/providers.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/bilingual.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_controller.dart';

final myRecoveriesProvider = FutureProvider.autoDispose<List<RecoveryHold>>(
  (ref) => ref.watch(accountsApiProvider).myRecoveries(),
);

/// Lost the old number: move the whole account to this one, by the email on
/// the old profile or by asking support (PRD F14 row 11).
class RecoverScreen extends ConsumerStatefulWidget {
  const RecoverScreen({super.key});

  @override
  ConsumerState<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends ConsumerState<RecoverScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _oldPhone = TextEditingController();
  final _business = TextEditingController();
  final _gstin = TextEditingController();
  final _payment = TextEditingController();
  String? _video;
  bool _codeSent = false;
  String? _devCode;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_email, _code, _oldPhone, _business, _gstin, _payment]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _guard(() async {
    final dev = await ref.read(accountsApiProvider).requestEmailRecovery(_email.text.trim());
    setState(() {
      _codeSent = true;
      _devCode = dev;
    });
  });

  Future<void> _recover() => _guard(() async {
    await ref.read(authControllerProvider.notifier).recoverByEmail(_email.text.trim(), _code.text.trim());
    if (mounted) context.go(Routes.splash); // the router opens the recovered account
  });

  Future<void> _recordVideo() async {
    final file = await ImagePicker().pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 12));
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _video = base64Encode(bytes));
  }

  int get _proofs => [_gstin.text.trim(), _payment.text.trim(), _video ?? ''].where((x) => x.isNotEmpty).length;

  Future<void> _submit() async {
    final s = context.s;
    final old = Phones.normalize(_oldPhone.text);
    if (old == null || _business.text.trim().length < 2) {
      showSnack(context, s.invalidPhone, error: true);
      return;
    }
    if (_proofs < 2) {
      showSnack(context, s.needTwoProofs, error: true);
      return;
    }
    await _guard(() async {
      await ref
          .read(accountsApiProvider)
          .submitRecovery(
            oldPhone: old,
            businessName: _business.text.trim(),
            gstin: _gstin.text.trim().isEmpty ? null : _gstin.text.trim(),
            paymentTxnId: _payment.text.trim().isEmpty ? null : _payment.text.trim(),
            selfieVideoBase64: _video,
          );
      ref.invalidate(myRecoveriesProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final mine = ref.watch(myRecoveriesProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(s.recoverTitle), actions: const [LangPill(), SizedBox(width: 8)]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            for (final r in mine)
              Card(
                key: Key('myRecovery-${r.id}'),
                child: ListTile(
                  leading: const Icon(Icons.support_agent_rounded),
                  title: Text(r.businessName),
                  subtitle: Text(s.recoveryStatus(r.status)),
                ),
              ),
            SectionHeader(s.recoverByEmail),
            Text(s.recoverByEmailHint, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('recoverEmail'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: s.emailLabel),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 12),
              if (_devCode != null) Text('Test code: $_devCode', style: const TextStyle(color: AppColors.muted)),
              TextField(
                key: const Key('recoverCode'),
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.codeLabel),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('recoverEmailButton'),
              onPressed: _busy ? null : (_codeSent ? _recover : _sendCode),
              child: Text(_codeSent ? s.recoverNow : s.sendCode),
            ),
            const SizedBox(height: 12),
            SectionHeader(s.recoverBySupport),
            Text(s.recoverBySupportHint, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            TextField(
              controller: _oldPhone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: s.oldNumber),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _business,
              decoration: InputDecoration(labelText: s.businessName),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _gstin,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: s.gstinOrLicence),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _payment,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: s.paymentId),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _recordVideo,
              icon: Icon(_video == null ? Icons.videocam_rounded : Icons.check_circle_rounded),
              label: Text(_video == null ? s.recordSelfieVideo : s.videoRecorded, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              key: const Key('recoverSupportButton'),
              onPressed: _busy ? null : _submit,
              child: Text('${s.sendRequest} · $_proofs/3'),
            ),
          ],
        ),
      ),
    );
  }
}
