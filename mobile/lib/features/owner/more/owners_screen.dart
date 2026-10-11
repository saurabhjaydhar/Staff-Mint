import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_controller.dart';

final ownersProvider = FutureProvider.autoDispose<List<OwnerItem>>((ref) => ref.watch(accountsApiProvider).owners());
final transferProvider = FutureProvider.autoDispose<TransferOffer?>(
  (ref) => ref.watch(accountsApiProvider).currentTransfer(),
);

/// Owners of this business: co-owners (billing only if allowed), handing the
/// business over, and recovering it when the main owner lost their number.
class OwnersScreen extends ConsumerWidget {
  const OwnersScreen({super.key});

  Future<(String, String, bool)?> _askPerson(
    BuildContext context, {
    required String title,
    bool withBilling = false,
  }) async {
    final s = context.s;
    final name = TextEditingController();
    final phone = TextEditingController();
    var billing = false;
    final ok = await showDialogWithControllers<bool>(
      context,
      [name, phone],
      (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('ownerName'),
                controller: name,
                decoration: InputDecoration(labelText: s.fullName),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('ownerPhone'),
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: s.mobileNumber),
              ),
              if (withBilling)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: billing,
                  title: Text(s.canManageBilling),
                  onChanged: (v) => setState(() => billing = v),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.add)),
          ],
        ),
      ),
    );
    final out = (name.text.trim(), phone.text.trim(), billing);
    if (ok != true) return null;
    if (out.$1.isEmpty || !Phones.isValid(out.$2)) {
      if (context.mounted) showSnack(context, s.invalidPhone, error: true);
      return null;
    }
    return out;
  }

  Future<void> _transfer(BuildContext context, WidgetRef ref) async {
    final s = context.s;
    final phone = TextEditingController();
    final code = TextEditingController();
    var keepAs = 'co_owner';
    var codeSent = false;
    final me = ref.read(authControllerProvider).user?.phone ?? '';
    final ok = await showDialogWithControllers<bool>(
      context,
      [phone, code],
      (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(s.transferBusiness),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.transferHint, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('transferPhone'),
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: s.newOwnerNumber),
                ),
                RadioGroup<String>(
                  groupValue: keepAs,
                  onChanged: (v) => setState(() => keepAs = v ?? keepAs),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'co_owner',
                        title: Text(s.stayCoOwner),
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'leave',
                        title: Text(s.leaveAfterTransfer),
                      ),
                    ],
                  ),
                ),
                if (codeSent)
                  TextField(
                    key: const Key('transferCode'),
                    controller: code,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: s.codeSentToYou),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
            FilledButton(
              onPressed: () async {
                if (!codeSent) {
                  // The main owner's own OTP confirms the handover.
                  await ref.read(authApiProvider).requestOtp(me);
                  setState(() => codeSent = true);
                } else {
                  Navigator.pop(ctx, true);
                }
              },
              child: Text(codeSent ? s.confirm : s.sendCode),
            ),
          ],
        ),
      ),
    );
    final to = Phones.normalize(phone.text);
    final c = code.text.trim();
    if (ok != true || to == null || !context.mounted) return;
    final done = await runGuarded(
      context,
      () => ref.read(accountsApiProvider).startTransfer(phone: to, keepAs: keepAs, code: c),
    );
    if (done) ref.invalidate(transferProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final owners = ref.watch(ownersProvider);
    final transfer = ref.watch(transferProvider).value;
    final api = ref.read(accountsApiProvider);
    final list = owners.value ?? const <OwnerItem>[];
    final iAmMain = list.any((o) => o.isYou && o.isMain);
    return Scaffold(
      appBar: AppBar(title: Text(s.ownersBi.text)),
      floatingActionButton: iAmMain
          ? FloatingActionButton.extended(
              key: const Key('addCoOwner'),
              icon: const Icon(Icons.group_add_rounded),
              label: Text(s.addCoOwner),
              onPressed: () async {
                final p = await _askPerson(context, title: s.addCoOwner, withBilling: true);
                if (p == null || !context.mounted) return;
                if (await runGuarded(context, () => api.addOwner(name: p.$1, phone: p.$2, canManageBilling: p.$3))) {
                  ref.invalidate(ownersProvider);
                }
              },
            )
          : null,
      body: owners.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(ownersProvider)),
        data: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Text(s.ownersHint, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 10),
            for (final o in items)
              Card(
                key: Key('owner-${o.id}'),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: o.isMain ? AppColors.mint : AppColors.mintLight,
                        child: Icon(Icons.person_rounded, color: o.isMain ? Colors.white : AppColors.mintDark),
                      ),
                      title: Text(
                        [o.name.isEmpty ? Phones.display(o.phone) : o.name, if (o.isYou) '(${s.you})'].join(' '),
                      ),
                      subtitle: Text('${o.isMain ? s.mainOwner : s.coOwner} · ${Phones.display(o.phone)}'),
                      trailing: iAmMain && !o.isMain
                          ? IconButton(
                              tooltip: s.remove,
                              icon: const Icon(Icons.person_remove_rounded, color: AppColors.red),
                              onPressed: () async {
                                if (!await confirmDialog(
                                  context,
                                  title: s.removeOwnerConfirm(o.name),
                                  destructive: true,
                                )) {
                                  return;
                                }
                                if (context.mounted && await runGuarded(context, () => api.removeOwner(o.id))) {
                                  ref.invalidate(ownersProvider);
                                }
                              },
                            )
                          : null,
                    ),
                    if (!o.isMain)
                      SwitchListTile(
                        key: Key('billing-${o.id}'),
                        value: o.canManageBilling,
                        title: Text(s.canManageBilling),
                        onChanged: iAmMain
                            ? (v) async {
                                if (await runGuarded(context, () => api.setOwnerBilling(o.id, v))) {
                                  ref.invalidate(ownersProvider);
                                }
                              }
                            : null,
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (transfer != null)
              Card(
                color: AppColors.amberLight,
                child: ListTile(
                  leading: const Icon(Icons.hourglass_top_rounded, color: AppColors.amberDark),
                  title: Text(s.transferPending(transfer.toPhoneMasked)),
                  trailing: TextButton(
                    onPressed: () async {
                      if (await runGuarded(context, api.cancelTransfer)) ref.invalidate(transferProvider);
                    },
                    child: Text(s.cancelTransfer),
                  ),
                ),
              )
            else if (iAmMain)
              Card(
                child: ListTile(
                  key: const Key('transferBusiness'),
                  leading: const Icon(Icons.swap_horiz_rounded),
                  title: Text(s.transferBusiness),
                  subtitle: Text(s.transferHint),
                  onTap: () => _transfer(context, ref),
                ),
              )
            else
              Card(
                child: ListTile(
                  key: const Key('ownerRecovery'),
                  leading: const Icon(Icons.phonelink_erase_rounded),
                  title: Text(s.ownerLostNumber),
                  subtitle: Text(s.ownerLostNumberHint),
                  onTap: () async {
                    final ctrl = TextEditingController();
                    final ok = await showDialogWithControllers<bool>(
                      context,
                      [ctrl],
                      (ctx) => AlertDialog(
                        title: Text(s.ownerLostNumber),
                        content: TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(labelText: s.ownersNewNumber),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.confirm)),
                        ],
                      ),
                    );
                    final to = Phones.normalize(ctrl.text);
                    if (ok != true || to == null || !context.mounted) return;
                    if (await runGuarded(context, () => api.startOwnerRecovery(to))) ref.invalidate(transferProvider);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
