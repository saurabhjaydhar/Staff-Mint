import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';

class PickedContact {
  const PickedContact({required this.name, required this.phone});
  final String name;
  final String phone;
}

/// Multi-select phone contacts picker. Pops with `List<PickedContact>`.
class ContactsPickerScreen extends StatefulWidget {
  const ContactsPickerScreen({super.key});

  @override
  State<ContactsPickerScreen> createState() => _ContactsPickerScreenState();
}

class _ContactsPickerScreenState extends State<ContactsPickerScreen> {
  List<PickedContact>? _all;
  final Set<String> _selected = {};
  String _query = '';
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
        setState(() => _denied = true);
        return;
      }
      final contacts = await FlutterContacts.getAll(properties: {ContactProperty.name, ContactProperty.phone});
      final seen = <String>{};
      final list = <PickedContact>[];
      for (final c in contacts) {
        for (final p in c.phones) {
          final phone = Phones.normalize(p.normalizedNumber ?? p.number);
          if (phone == null || !seen.add(phone)) continue;
          final name = (c.displayName ?? '').trim();
          list.add(PickedContact(name: name.isEmpty ? phone : name, phone: phone));
          break;
        }
      }
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) setState(() => _all = list);
    } catch (_) {
      if (mounted) setState(() => _denied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final filtered = (_all ?? const <PickedContact>[])
        .where((c) => _query.isEmpty || c.name.toLowerCase().contains(_query) || c.phone.contains(_query))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty ? s.pickFromContacts : s.selectedCount(_selected.length)),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, _all!.where((c) => _selected.contains(c.phone)).toList()),
            child: Text(s.add),
          ),
        ],
      ),
      body: _denied
          ? EmptyView(message: s.contactsPermissionDenied, icon: Icons.contacts_outlined)
          : _all == null
          ? const LoadingView()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s.searchStaff),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? EmptyView(message: s.noContactsWithPhone)
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final c = filtered[i];
                            return CheckboxListTile(
                              value: _selected.contains(c.phone),
                              secondary: InitialsAvatar(c.name),
                              title: Text(c.name),
                              subtitle: Text(Phones.display(c.phone)),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selected.add(c.phone);
                                } else {
                                  _selected.remove(c.phone);
                                }
                              }),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
