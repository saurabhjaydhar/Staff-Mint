import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/shift_chip.dart';
import '../../auth/auth_controller.dart';
import '../employee_providers.dart';

String _day(S s, String date) => Dates.weekdayShort(DateTime.parse(date), s.languageCode);

String _what(S s, MyRosterWeek? week, SwapSide side) {
  if (side.isOff) return s.dayOff;
  final sh = week?.shiftById(side.shiftId);
  return sh == null ? '' : '${sh.name} ${shortHours(sh)}';
}

/// Staff home: a colleague's request to answer, and how the person's own requests are doing.
class MySwaps extends ConsumerWidget {
  const MySwaps({super.key, required this.week});
  final MyRosterWeek? week;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final me = ref.watch(authControllerProvider.select((v) => v.user?.employeeId));
    final today = Dates.toApiDate(DateTime.now());
    final list = [
      for (final x in ref.watch(mySwapsProvider).value ?? const <RosterSwap>[])
        if (x.date.compareTo(today) >= 0 && x.status != 'expired') x,
    ];
    final incoming = [
      for (final x in list)
        if (x.to.employeeId == me && x.status == 'asked') x,
    ];
    final mine = [
      for (final x in list)
        if (x.from.employeeId == me) x,
    ];
    if (incoming.isEmpty && mine.isEmpty) return const SizedBox.shrink();

    Future<void> act(RosterSwap x, String action, String done) async {
      final ok = await runGuarded(context, () => ref.read(rosterApiProvider).swapAction(x.id, action));
      if (!ok || !context.mounted) return;
      ref.invalidate(mySwapsProvider);
      showSnack(context, done);
    }

    String status(RosterSwap x) => switch (x.status) {
      'asked' => s.swapWaitingFor(x.to.name),
      'accepted' => s.swapWaitingOwner,
      'approved' => s.swapApprovedTag,
      'declined' => s.swapDeclinedTag(x.to.name),
      'rejected' => s.swapRejectedTag,
      _ => s.swapCancelledTag,
    };

    return Padding(
      key: const Key('mySwaps'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        children: [
          for (final x in incoming)
            Card(
              key: Key('swapIncoming_${x.id}'),
              color: AppColors.amberLight,
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.swapIncoming(x.from.name, _day(s, x.date)),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.swapIncomingDetail(_what(s, week, x.from), _what(s, week, x.to)),
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    Row(
                      children: [
                        FilledButton(
                          key: Key('swapAccept_${x.id}'),
                          onPressed: () => act(x, 'accept', s.swapAccepted),
                          child: Text(s.swapYes),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          key: Key('swapDecline_${x.id}'),
                          onPressed: () => act(x, 'decline', s.swapDeclined),
                          child: Text(s.swapNo),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          for (final x in mine)
            Card(
              key: Key('swapMine_${x.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  Icons.swap_horiz_rounded,
                  color: x.status == 'approved' ? AppColors.mintDark : (x.open ? AppColors.amberDark : AppColors.muted),
                ),
                title: Text(
                  s.swapWith(x.to.name, _day(s, x.date)),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(status(x)),
                trailing: x.open
                    ? TextButton(
                        key: Key('swapCancel_${x.id}'),
                        onPressed: () => act(x, 'cancel', s.swapCancelledTag),
                        child: Text(s.cancel),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Ask a colleague to swap a day: pick the day, pick the person, check what each gets, ask.
Future<void> showSwapSheet(BuildContext context, MyRosterWeek week) async {
  final asked = await showModalBottomSheet<String>(
    context: context,
    // Above the bottom tabs, so the Ask button is never hidden behind them.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.paper,
    builder: (_) => _SwapSheet(week: week),
  );
  if (asked != null && context.mounted) showSnack(context, context.s.swapAsked(asked));
}

class _SwapSheet extends ConsumerStatefulWidget {
  const _SwapSheet({required this.week});
  final MyRosterWeek week;

  @override
  ConsumerState<_SwapSheet> createState() => _SwapSheetState();
}

class _SwapSheetState extends ConsumerState<_SwapSheet> {
  String? _date;
  Future<SwapOptions>? _options;
  SwapOption? _with;
  bool _busy = false;

  void _pickDay(String date) => setState(() {
    _date = date;
    _with = null;
    _options = ref.read(rosterApiProvider).swapOptions(date);
  });

  Future<void> _ask() async {
    final w = _with!;
    setState(() => _busy = true);
    final ok = await runGuarded(context, () => ref.read(rosterApiProvider).askSwap(_date!, w.employeeId));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(mySwapsProvider);
      Navigator.pop(context, w.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final today = Dates.toApiDate(DateTime.now());
    final days = [
      for (final d in widget.week.days)
        if (d.date.compareTo(today) >= 0 && d.leave == null) d,
    ];
    Widget title(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
    );
    return SingleChildScrollView(
      key: const Key('swapSheet'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.swapADay, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          title(s.swapPickDay),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in days)
                ChoiceChip(
                  key: Key('swapDay_${d.date}'),
                  label: Text(
                    '${_day(s, d.date)} · ${d.kind == 'off' ? s.dayOff : (widget.week.shiftById(d.shiftId)?.name ?? '')}',
                  ),
                  selected: _date == d.date,
                  onSelected: (_) => _pickDay(d.date),
                ),
            ],
          ),
          if (_options != null)
            FutureBuilder<SwapOptions>(
              future: _options,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(padding: const EdgeInsets.only(top: 12), child: Text(errorMessage(context, snap.error!)));
                }
                final o = snap.data;
                if (o == null) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title(s.swapPickPerson),
                    if (o.colleagues.isEmpty) Text(s.swapNobody, style: const TextStyle(color: AppColors.muted)),
                    for (final c in o.colleagues)
                      Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        color: _with?.employeeId == c.employeeId ? AppColors.mintFaint : null,
                        child: ListTile(
                          key: Key('swapWith_${c.employeeId}'),
                          leading: InitialsAvatar(c.name),
                          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(c.label),
                          trailing: _with?.employeeId == c.employeeId
                              ? const Icon(Icons.check_circle_rounded, color: AppColors.mint)
                              : null,
                          onTap: () => setState(() => _with = c),
                        ),
                      ),
                    if (_with != null) ...[
                      title(s.swapConfirm(_with!.name, _day(s, o.date))),
                      Text(s.swapYouGet(_with!.label), style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(s.swapTheyGet(_with!.name, o.mineLabel)),
                      const SizedBox(height: 4),
                      Text(s.swapOwnerApproves, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const Key('swapAsk'),
                          onPressed: _busy ? null : _ask,
                          child: Text(s.swapAsk),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
