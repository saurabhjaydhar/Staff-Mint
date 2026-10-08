import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/locale_provider.dart';
import '../../core/i18n/strings.dart';
import '../../core/router/routes.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/common.dart';
import 'auth_controller.dart';
import 'splash_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit({String channel = 'sms'}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final phone = Phones.normalize(_phone.text)!;
    setState(() => _busy = true);
    try {
      final res = await ref.read(authControllerProvider.notifier).requestOtp(phone, channel: channel);
      if (!mounted) return;
      unawaited(
        context.push<void>(
          Uri(
            path: Routes.otp,
            queryParameters: {'phone': phone, 'channel': channel, if (res.devCode != null) 'devCode': res.devCode!},
          ).toString(),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final lang = ref.watch(localeProvider);
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: LanguageToggle(value: lang, onChanged: (v) => ref.read(localeProvider.notifier).setLanguage(v)),
              ),
              const SizedBox(height: 32),
              const Center(child: BrandMark(size: 72)),
              const SizedBox(height: 20),
              Text(
                s.loginTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                s.taglineHinglish,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 40),
              Text(s.loginSubtitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('phoneField'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                style: const TextStyle(fontSize: 22, letterSpacing: 1.5),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                  LengthLimitingTextInputFormatter(16),
                ],
                decoration: InputDecoration(
                  labelText: s.mobileNumber,
                  prefixText: '+91 ',
                  prefixIcon: const Icon(Icons.phone_android_rounded),
                ),
                validator: (v) => Phones.isValid(v ?? '') ? null : s.invalidPhone,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('getOtpButton'),
                onPressed: _busy ? null : () => _submit(),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(s.getOtp),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy ? null : () => _submit(channel: 'whatsapp'),
                icon: const Icon(Icons.chat_rounded),
                label: Text(s.sendViaWhatsApp),
              ),
              const SizedBox(height: 24),
              Text(s.termsNote, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
