import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/bilingual.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_controller.dart';

/// First question for a number StaffMint doesn't know: owner or staff?
/// Staff must not create a business by accident.
class WhoAreYouView extends StatelessWidget {
  const WhoAreYouView({super.key, required this.onOwner, required this.onStaff});
  final VoidCallback onOwner;
  final VoidCallback onStaff;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(actions: const [LangPill(), SizedBox(width: 8)]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(s.whoAreYou, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(s.whoAreYouHint, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
            const SizedBox(height: 24),
            _ChoiceCard(
              key: const Key('iAmOwner'),
              icon: Icons.storefront_rounded,
              title: s.iOwnBusiness,
              subtitle: s.iOwnBusinessHint,
              onTap: onOwner,
            ),
            const SizedBox(height: 14),
            _ChoiceCard(
              key: const Key('iAmStaff'),
              icon: Icons.badge_rounded,
              title: s.iWorkAtShop,
              subtitle: s.iWorkAtShopHint,
              onTap: onStaff,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppColors.line, width: 1.5),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: AppColors.mintDark, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

/// Staff whose number the owner hasn't added yet. "Check again" re-asks the
/// server, which links the login as soon as the owner adds this number.
class WaitingForEmployerView extends ConsumerStatefulWidget {
  const WaitingForEmployerView({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  ConsumerState<WaitingForEmployerView> createState() => _WaitingForEmployerViewState();
}

class _WaitingForEmployerViewState extends ConsumerState<WaitingForEmployerView> {
  bool _busy = false;

  Future<void> _check() async {
    final s = context.s;
    setState(() => _busy = true);
    try {
      final linked = await ref.read(authControllerProvider.notifier).recheckStaffLink();
      // When linked, the router moves on to the staff screens by itself.
      if (!linked && mounted) showSnack(context, s.notAddedYet, error: true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final phone = ref.watch(authControllerProvider).user?.phone ?? '';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        actions: const [LangPill(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            const Center(
              child: CircleAvatar(
                radius: 44,
                backgroundColor: AppColors.amberLight,
                child: Icon(Icons.hourglass_top_rounded, size: 44, color: AppColors.amberDark),
              ),
            ),
            const SizedBox(height: 20),
            Text(s.askEmployerTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              s.askEmployerBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line, width: 1.5),
              ),
              child: Column(
                children: [
                  Text(s.yourNumber, style: const TextStyle(color: AppColors.muted)),
                  Text(
                    Phones.display(phone),
                    key: const Key('waitingPhone'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const Key('checkAgain'),
                onPressed: _busy ? null : _check,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(s.checkAgain),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => ref.read(authControllerProvider.notifier).logout(),
              child: Text(s.useAnotherNumber),
            ),
          ],
        ),
      ),
    );
  }
}
