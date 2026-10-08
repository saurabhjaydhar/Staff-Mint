import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/widgets/common.dart';
import '../providers/owner_providers.dart';

class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final config = ref.watch(publicConfigProvider).value;
    final whatsapp = config?.supportWhatsApp;
    final faqs = [(s.faq1q, s.faq1a), (s.faq2q, s.faq2a), (s.faq3q, s.faq3a), (s.faq4q, s.faq4a)];
    return Scaffold(
      appBar: AppBar(title: Text(s.helpTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (whatsapp != null && whatsapp.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                icon: const Icon(Icons.chat_rounded),
                label: Text(s.chatOnWhatsApp),
                onPressed: () => openUrl(context, 'https://wa.me/${whatsapp.replaceAll(RegExp(r'[^0-9]'), '')}'),
              ),
            ),
          for (final (q, a) in faqs)
            Card(
              child: ExpansionTile(
                title: Text(q, style: Theme.of(context).textTheme.titleMedium),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [Text(a, style: Theme.of(context).textTheme.bodyLarge)],
              ),
            ),
          ListTile(title: Text(s.appVersion), trailing: const Text('1.0.0')),
        ],
      ),
    );
  }
}
