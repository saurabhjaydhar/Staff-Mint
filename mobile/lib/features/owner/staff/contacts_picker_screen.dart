import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/common.dart';
import 'contact_rows.dart';

class PickedContact {
  const PickedContact({required this.name, required this.phone});
  final String name;
  final String phone;
}

/// Multi-select picker over the phone's own contacts. Pops with `List<PickedContact>`.
/// Nothing leaves the phone except the people the owner ticks.
class ContactsPickerScreen extends StatefulWidget {
  const ContactsPickerScreen({super.key, this.loadContacts});

  /// Test seam: returns (rows, onlySomeShared). Defaults to the phone's contacts.
  final Future<(List<ContactRow>, bool)> Function()? loadContacts;

  @override
  State<ContactsPickerScreen> createState() => _ContactsPickerScreenState();
}

class _ContactsPickerScreenState extends State<ContactsPickerScreen> {
  List<ContactRow>? _all;
  final Set<String> _selected = {};
  String _query = '';
  bool _denied = false;

  /// The phone shared only some contacts (Android 14+ / iOS "limited access").
  bool _limited = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static Future<(List<ContactRow>, bool)> _fromPhone() async {
    final status = await FlutterContacts.permissions.request(PermissionType.read);
    if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
      throw const _Denied();
    }
    final contacts = await FlutterContacts.getAll(properties: {ContactProperty.name, ContactProperty.phone});
    final rows = buildContactRows(
      contacts.map((c) => (c.displayName ?? '', [for (final p in c.phones) (p.number, p.normalizedNumber)])),
    );
    return (rows, status == PermissionStatus.limited);
  }

  Future<void> _load() async {
    try {
      final (rows, limited) = await (widget.loadContacts ?? _fromPhone)();
      if (mounted) {
        setState(() {
          _all = rows;
          _limited = limited;
          _denied = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _denied = true);
    }
  }

  Future<void> _openSettings() async {
    try {
      await FlutterContacts.permissions.openSettings();
    } catch (_) {}
  }

  bool _matches(ContactRow c) {
    if (_query.isEmpty) return true;
    final digits = _query.replaceAll(RegExp(r'\D'), '');
    return c.name.toLowerCase().contains(_query) ||
        (digits.isNotEmpty && (c.phone ?? c.shown).replaceAll(RegExp(r'\D'), '').contains(digits));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final all = _all ?? const <ContactRow>[];
    final filtered = all.where(_matches).toList();
    final firstNoMobile = filtered.indexWhere((c) => !c.canAdd);
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty ? s.pickFromContacts : s.selectedCount(_selected.length)),
        actions: [
          TextButton(
            key: const Key('contactsAdd'),
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, [
                    for (final c in all)
                      if (c.phone != null && _selected.contains(c.phone)) PickedContact(name: c.name, phone: c.phone!),
                  ]),
            child: Text(s.add),
          ),
        ],
      ),
      body: _denied
          ? EmptyView(
              message: s.contactsPermissionDenied,
              icon: Icons.contacts_outlined,
              action: OutlinedButton(onPressed: _openSettings, child: Text(s.openSettings)),
            )
          : _all == null
          ? const LoadingView()
          : Column(
              children: [
                if (_limited)
                  Container(
                    key: const Key('contactsLimited'),
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                    decoration: BoxDecoration(color: AppColors.amberLight, borderRadius: AppTheme.radius),
                    child: Row(
                      children: [
                        Expanded(child: Text(s.contactsOnlySome)),
                        TextButton(onPressed: _openSettings, child: Text(s.allowAll)),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s.searchStaff),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      s.contactsCount(all.length, all.where((c) => c.canAdd).length),
                      key: const Key('contactsCount'),
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? EmptyView(message: s.noContactsWithPhone)
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final c = filtered[i];
                            final tile = c.canAdd
                                ? CheckboxListTile(
                                    key: Key('contact_${c.phone}'),
                                    value: _selected.contains(c.phone),
                                    secondary: InitialsAvatar(c.name),
                                    title: Text(c.name),
                                    subtitle: Text(Phones.display(c.phone!)),
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        _selected.add(c.phone!);
                                      } else {
                                        _selected.remove(c.phone);
                                      }
                                    }),
                                  )
                                : ListTile(
                                    enabled: false,
                                    leading: InitialsAvatar(c.name),
                                    title: Text(c.name),
                                    subtitle: Text('${c.shown} · ${s.notAMobile}'),
                                  );
                            if (i != firstNoMobile) return tile;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                                  child: Text(
                                    s.cantAddContacts,
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted),
                                  ),
                                ),
                                tile,
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _Denied implements Exception {
  const _Denied();
}
