import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_controller.dart';

/// DPDP-style notice shown on an employee's first login.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _busy = false;

  Future<void> _agree() async {
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).giveConsent();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final session = ref.watch(authControllerProvider);
    final lang = ref.watch(localeProvider);
    final company = session.company?.name ?? s.yourEmployer;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.consentTitle),
        actions: [
          TextButton(
            onPressed: () => ref.read(localeProvider.notifier).toggle(),
            child: Text(lang == 'hi' ? s.english : s.hindi),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Center(
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.mintLight,
                      child: Icon(Icons.privacy_tip_rounded, size: 44, color: AppColors.mintDark),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(s.consentBody(company), style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _agree,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(s.consentAgree, textAlign: TextAlign.center),
                ),
              ),
            ),
            TextButton(onPressed: () => ref.read(authControllerProvider.notifier).logout(), child: Text(s.logout)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
