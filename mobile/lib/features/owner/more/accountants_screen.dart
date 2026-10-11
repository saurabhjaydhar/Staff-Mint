import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';

final accountantsProvider = FutureProvider.autoDispose<List<Accountant>>(
  (ref) => ref.watch(accountsApiProvider).accountants(),
);

/// Owner's accountants (CA): read-only access to reports, payroll and export.
class AccountantsScreen extends ConsumerWidget {
  const AccountantsScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final s = context.s;
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialogWithControllers<bool>(
      context,
      [name, phone],
      (ctx) => AlertDialog(
        title: Text(s.addAccountant),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('caName'),
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: s.fullName),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('caPhone'),
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: s.mobileNumber),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.add)),
        ],
      ),
    );
    final n = name.text.trim();
    final p = phone.text.trim();
    if (ok != true || !context.mounted) return;
    if (n.isEmpty || !Phones.isValid(p)) {
      showSnack(context, s.invalidPhone, error: true);
      return;
    }
    final done = await runGuarded(
      context,
      () => ref.read(accountsApiProvider).addAccountant(phone: p, name: n),
      success: s.saved,
    );
    if (done) ref.invalidate(accountantsProvider);
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, Accountant a) async {
    final s = context.s;
    final ok = await confirmDialog(
      context,
      title: s.removeAccountantConfirm(a.name.isEmpty ? Phones.display(a.phone) : a.name),
      confirmLabel: s.remove,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final done = await runGuarded(context, () => ref.read(accountsApiProvider).removeAccountant(a.id));
    if (done) ref.invalidate(accountantsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final list = ref.watch(accountantsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.accountantsBi.text)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addAccountant'),
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(s.addAccountant),
      ),
      body: list.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(accountantsProvider)),
        data: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Text(s.accountantsHint, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(s.noAccountants, style: const TextStyle(color: AppColors.muted)),
                ),
              ),
            for (final a in items)
              Card(
                child: ListTile(
                  key: Key('accountant-${a.id}'),
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.orangeLight,
                    child: Icon(Icons.calculate_rounded, color: AppColors.orange),
                  ),
                  title: Text(a.name.isEmpty ? Phones.display(a.phone) : a.name),
                  subtitle: Text(Phones.display(a.phone)),
                  trailing: IconButton(
                    tooltip: s.remove,
                    icon: const Icon(Icons.person_remove_rounded, color: AppColors.red),
                    onPressed: () => _remove(context, ref, a),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
