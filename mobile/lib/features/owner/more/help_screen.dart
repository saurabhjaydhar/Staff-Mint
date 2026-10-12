import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../providers/owner_providers.dart';
import '../today/home_tips.dart';
import 'help_content.dart';

/// Short answers grouped by task, a search box, "show tips again" and WhatsApp.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final config = ref.watch(publicConfigProvider).value;
    final whatsapp = config?.supportWhatsApp;
    final q = _q.trim().toLowerCase();
    final groups = [
      for (final (title, items) in helpGroups(s))
        (
          title,
          [
            for (final it in items)
              if (q.isEmpty || '${it.$1} ${it.$2}'.toLowerCase().contains(q)) it,
          ],
        ),
    ].where((g) => g.$2.isNotEmpty).toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.helpTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              key: const Key('helpSearch'),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s.helpSearch),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(s.nothingFound, textAlign: TextAlign.center),
            ),
          for (final (title, items) in groups) ...[
            SectionHeader(title),
            for (final (question, answer) in items)
              Card(
                child: ExpansionTile(
                  title: Text(question, style: Theme.of(context).textTheme.titleMedium),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(answer, style: Theme.of(context).textTheme.bodyLarge)],
                ),
              ),
          ],
          Card(
            child: ListTile(
              key: const Key('helpTipsAgain'),
              leading: const Icon(Icons.replay_rounded, color: AppColors.mintDark),
              title: Text(s.showTipsAgain),
              onTap: () async {
                await HomeTips.replay(ref);
                if (context.mounted) showSnack(context, s.tipsWillShow);
              },
            ),
          ),
          if (whatsapp != null && whatsapp.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.whatsapp),
                icon: const Icon(Icons.chat_rounded),
                label: Text(s.chatOnWhatsApp),
                onPressed: () => openUrl(context, 'https://wa.me/${whatsapp.replaceAll(RegExp(r'[^0-9]'), '')}'),
              ),
            ),
          ListTile(
            title: Text(s.appVersion),
            trailing: const Text('1.0.0', style: TextStyle(color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}
