import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../providers/owner_providers.dart';

class HolidaysScreen extends ConsumerStatefulWidget {
  const HolidaysScreen({super.key});

  @override
  ConsumerState<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends ConsumerState<HolidaysScreen> {
  int _year = DateTime.now().year;

  Future<void> _add() async {
    final s = context.s;
    final name = TextEditingController();
    DateTime date = DateTime(_year, DateTime.now().month, DateTime.now().day);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(s.addHoliday),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(labelText: s.holidayName),
              ),
              const SizedBox(height: 12),
              DateField(
                label: s.date,
                value: date,
                firstDate: DateTime(_year),
                lastDate: DateTime(_year, 12, 31),
                onChanged: (d) => setLocal(() => date = d),
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
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    if (await runGuarded(
      context,
      () => ref.read(companyApiProvider).addHoliday(Dates.toApiDate(date), name.text.trim()),
      success: s.saved,
    )) {
      ref.invalidate(holidaysProvider(_year));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final holidays = ref.watch(holidaysProvider(_year));
    return Scaffold(
      appBar: AppBar(
        title: Text(s.holidays),
        actions: [IconButton(tooltip: s.addHoliday, icon: const Icon(Icons.add), onPressed: _add)],
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 32),
                onPressed: () => setState(() => _year--),
              ),
              Text('$_year', style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 32),
                onPressed: () => setState(() => _year++),
              ),
            ],
          ),
          Expanded(
            child: AsyncBody<List<Holiday>>(
              value: holidays,
              onRetry: () => ref.invalidate(holidaysProvider(_year)),
              data: (list) {
                final sorted = [...list]..sort((a, b) => a.date.compareTo(b.date));
                return RefreshableList(
                  onRefresh: () => ref.refresh(holidaysProvider(_year).future),
                  children: [
                    if (sorted.isEmpty) EmptyView(message: s.noHolidays, icon: Icons.celebration_outlined),
                    for (final h in sorted)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.celebration_rounded),
                          title: Text(h.name),
                          subtitle: Text(Dates.prettyApiDate(h.date, s.languageCode)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            tooltip: s.delete,
                            onPressed: () async {
                              if (!await confirmDialog(context, title: s.delete, message: h.name, destructive: true)) {
                                return;
                              }
                              if (!context.mounted) return;
                              if (await runGuarded(context, () => ref.read(companyApiProvider).deleteHoliday(h.id))) {
                                ref.invalidate(holidaysProvider(_year));
                              }
                            },
                          ),
                        ),
                      ),
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
