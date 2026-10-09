import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/bilingual.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/pickers.dart';
import '../employee_providers.dart';

class EmployeeLeaveScreen extends ConsumerWidget {
  const EmployeeLeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final leaves = ref.watch(myLeavesProvider);
    final balances = ref.watch(myLeaveBalancesProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => const _ApplyLeaveSheet(),
          );
          if (ok == true) {
            ref.invalidate(myLeavesProvider);
            ref.invalidate(myLeaveBalancesProvider);
          }
        },
        icon: const Icon(Icons.add),
        label: Text(s.applyLeave),
      ),
      body: SafeArea(
        child: RefreshableList(
          onRefresh: () async {
            ref.invalidate(myLeaveBalancesProvider);
            ref.invalidate(myLeavesProvider);
            await ref.read(myLeavesProvider.future);
          },
          children: [
            ScreenHeader(subtitle: s.navLeaveBi.joined, title: s.myLeaves),
            SectionHeader(s.balances),
            balances.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(error: e),
              data: (list) {
                final b = list.firstOrNull;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _BalanceTile(
                        label: s.paidLeft(b?.paidLeft ?? 0),
                        icon: Icons.beach_access_rounded,
                        fg: AppColors.indigo,
                        bg: AppColors.indigoLight,
                      ),
                      _BalanceTile(
                        label: s.sickLeft(b?.sickLeft ?? 0),
                        icon: Icons.medical_services_rounded,
                        fg: AppColors.orange,
                        bg: AppColors.orangeLight,
                      ),
                    ],
                  ),
                );
              },
            ),
            SectionHeader(s.myLeaves),
            leaves.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myLeavesProvider)),
              data: (list) => list.isEmpty
                  ? EmptyView(message: s.nothingHere, icon: Icons.beach_access_outlined)
                  : Column(
                      children: [
                        for (final l in list)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.beach_access_rounded, color: AppColors.indigo),
                              title: Text(s.leaveTypeLabel(l.type)),
                              subtitle: Text(
                                [
                                  '${Dates.prettyApiDate(l.from, s.languageCode)} – ${Dates.prettyApiDate(l.to, s.languageCode)}',
                                  if (l.halfDay) s.halfDayLeave,
                                  if (l.note != null && l.note!.isNotEmpty) l.note!,
                                ].join(' · '),
                              ),
                              trailing: l.isPending
                                  ? TextButton(
                                      onPressed: () async {
                                        if (await runGuarded(context, () => ref.read(leaveApiProvider).cancel(l.id))) {
                                          ref.invalidate(myLeavesProvider);
                                        }
                                      },
                                      child: Text(s.cancelLeave),
                                    )
                                  : Text(
                                      s.leaveStatusLabel(l.status),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: l.status == 'approved'
                                            ? AppColors.mint
                                            : l.status == 'rejected'
                                            ? AppColors.red
                                            : AppColors.muted,
                                      ),
                                    ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({required this.label, required this.icon, required this.fg, required this.bg});
  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Icon(icon, color: fg),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg),
          ),
        ],
      ),
    ),
  );
}

class _ApplyLeaveSheet extends ConsumerStatefulWidget {
  const _ApplyLeaveSheet();

  @override
  ConsumerState<_ApplyLeaveSheet> createState() => _ApplyLeaveSheetState();
}

class _ApplyLeaveSheetState extends ConsumerState<_ApplyLeaveSheet> {
  String _type = 'paid';
  DateTime _from = Dates.today().add(const Duration(days: 1));
  DateTime _to = Dates.today().add(const Duration(days: 1));
  bool _halfDay = false;
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final s = context.s;
    final ok = await runGuarded(context, () async {
      await ref
          .read(leaveApiProvider)
          .apply(
            type: _type,
            from: Dates.toApiDate(_from),
            to: Dates.toApiDate(_halfDay ? _from : _to),
            halfDay: _halfDay,
            reason: _reason.text.trim(),
          );
    }, success: s.leaveApplied);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final now = DateTime.now();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(s.applyLeave, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final t in const ['paid', 'sick', 'unpaid'])
                ChoiceChip(
                  label: Text(s.leaveTypeLabel(t)),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _halfDay,
            title: Text(s.halfDayLeave),
            onChanged: (v) => setState(() => _halfDay = v),
          ),
          DateField(
            label: s.from,
            value: _from,
            firstDate: DateTime(now.year - 1),
            onChanged: (d) => setState(() {
              _from = d;
              if (_to.isBefore(d)) _to = d;
            }),
          ),
          if (!_halfDay) ...[
            const SizedBox(height: 12),
            DateField(label: s.to, value: _to, firstDate: _from, onChanged: (d) => setState(() => _to = d)),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: InputDecoration(labelText: '${s.reason} (${s.optional})'),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(s.applyLeave)),
        ],
      ),
    );
  }
}
