import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/providers.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/router/routes.dart';
import '../../core/utils/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/bilingual.dart';
import '../../core/widgets/common.dart';
import '../owner/staff/contacts_picker_screen.dart';
import '../owner/staff/quick_staff_dialog.dart';
import 'setup_screen.dart' show SetupProgress;

/// Step 5 of setup: add staff manually / from contacts, or skip.
class SetupStaffScreen extends ConsumerStatefulWidget {
  const SetupStaffScreen({super.key});

  @override
  ConsumerState<SetupStaffScreen> createState() => _SetupStaffScreenState();
}

class _SetupStaffScreenState extends ConsumerState<SetupStaffScreen> {
  final List<NewEmployee> _drafts = [];
  bool _busy = false;

  void _addAll(Iterable<NewEmployee> list) {
    setState(() {
      for (final e in list) {
        final phone = Phones.normalize(e.phone);
        if (phone == null) continue;
        if (_drafts.any((d) => Phones.normalize(d.phone) == phone)) continue;
        _drafts.add(e);
      }
    });
  }

  Future<void> _manual() async {
    final e = await showQuickStaffDialog(context);
    if (e != null) _addAll([e]);
  }

  Future<void> _contacts() async {
    final picked = await Navigator.of(
      context,
    ).push<List<PickedContact>>(MaterialPageRoute(builder: (_) => const ContactsPickerScreen()));
    if (picked != null) {
      _addAll(picked.map((c) => NewEmployee(name: c.name, phone: c.phone)));
    }
  }

  Future<void> _finish() async {
    if (_drafts.isEmpty) {
      context.go(Routes.ownerHome);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await ref.read(employeesApiProvider).bulkCreate(_drafts);
      if (!mounted) return;
      final s = context.s;
      showSnack(
        context,
        [s.staffAdded(res.created.length), if (res.skipped.isNotEmpty) s.staffSkipped(res.skipped.length)].join(' · '),
      );
      context.go(Routes.ownerHome);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(s.setupStep(5, 5)),
        actions: const [LangPill(), SizedBox(width: 8)],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(14), child: SetupProgress(step: 4, total: 5)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(s.setupStaffTitle, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    s.setupStaffHint,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 20),
                  // Picking many contacts at once is the fast path; manual entry is the fallback.
                  FilledButton.icon(
                    onPressed: _contacts,
                    icon: const Icon(Icons.contacts_rounded),
                    label: Text(s.pickFromContacts),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _manual,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(s.addManually),
                  ),
                  const SizedBox(height: 16),
                  for (final d in _drafts)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: InitialsAvatar(d.name),
                        title: Text(d.name),
                        subtitle: Text(
                          [
                            Phones.display(d.phone),
                            if (d.ratePaise != null) s.perMonth(Money.format(d.ratePaise!)),
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() => _drafts.remove(d)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _finish,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(_drafts.isEmpty ? s.finishSetup : '${s.finishSetup} (${_drafts.length})'),
                    ),
                  ),
                  TextButton(onPressed: _busy ? null : () => context.go(Routes.ownerHome), child: Text(s.skipForNow)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
