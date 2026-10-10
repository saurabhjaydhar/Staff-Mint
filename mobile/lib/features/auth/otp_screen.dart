import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/common.dart';
import 'auth_controller.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone, this.devCode, this.channel = 'sms'});
  final String phone;
  final String? devCode;
  final String channel;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _devCode;
  int _resendIn = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _devCode = widget.devCode;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 4) return;
    setState(() => _busy = true);
    try {
      // On success the router redirects automatically (auth state changes).
      final check = await ref.read(authControllerProvider.notifier).verifyOtp(widget.phone, code);
      if (check != null && mounted) await _askIdentity(check);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The number was idle for months and this phone is new: it may belong to someone else now.
  Future<void> _askIdentity(IdentityCheck check) async {
    final s = context.s;
    final isMe = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.person_search_rounded, size: 34, color: AppColors.mintDark),
        title: Text(s.isThisYou(check.maskedName)),
        content: Text(s.isThisYouBody),
        actions: [
          TextButton(key: const Key('identityNo'), onPressed: () => Navigator.pop(ctx, false), child: Text(s.notMe)),
          FilledButton(
            key: const Key('identityYes'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.yesItsMe),
          ),
        ],
      ),
    );
    if (isMe == null || !mounted) return;
    await ref.read(authControllerProvider.notifier).answerIdentity(check.token, isMe: isMe);
  }

  Future<void> _resend() async {
    try {
      final res = await ref.read(authControllerProvider.notifier).requestOtp(widget.phone, channel: widget.channel);
      if (!mounted) return;
      setState(() => _devCode = res.devCode ?? _devCode);
      _startTimer();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.otpTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              s.otpSentTo(Phones.display(widget.phone)),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
            ),
            if (_devCode != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Icon(Icons.developer_mode_rounded, color: AppColors.mintDark),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.devCodeHint(_devCode!), key: const Key('devCodeHint'))),
                    TextButton(
                      onPressed: () {
                        _code.text = _devCode!;
                        _verify();
                      },
                      child: Text(s.ok),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              autofillHints: const [AutofillHints.oneTimeCode],
              style: const TextStyle(fontSize: 32, letterSpacing: 12, fontWeight: FontWeight.w700),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              decoration: const InputDecoration(hintText: '••••••', counterText: ''),
              onChanged: (v) {
                if (v.length == 6) _verify();
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _verify,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(s.verify),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(s.changeNumber)),
                TextButton(
                  onPressed: _resendIn == 0 ? _resend : null,
                  child: Text(_resendIn == 0 ? s.resendOtp : s.resendIn(_resendIn)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
