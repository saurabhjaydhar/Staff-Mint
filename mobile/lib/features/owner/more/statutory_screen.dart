import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';

/// PF, ESI & Professional Tax for the shop. Off for most small shops; each part explains itself.
class StatutoryScreen extends ConsumerStatefulWidget {
  const StatutoryScreen({super.key});

  @override
  ConsumerState<StatutoryScreen> createState() => _StatutoryScreenState();
}

class _StatutoryScreenState extends ConsumerState<StatutoryScreen> {
  StatutorySettings? _st;
  Object? _error;
  bool _saving = false;
  final _pfNo = TextEditingController();
  final _esiNo = TextEditingController();
  final _ptState = TextEditingController();
  final _ptAmount = TextEditingController();
  final _ptMin = TextEditingController();
  bool _pf = false, _esi = false, _pt = false;
  int _basic = 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_pfNo, _esiNo, _ptState, _ptAmount, _ptMin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final st = await ref.read(companyApiProvider).statutory();
      if (!mounted) return;
      setState(() {
        _st = st;
        _pf = st.pfEnabled;
        _esi = st.esiEnabled;
        _pt = st.ptEnabled;
        _basic = st.basicPercent;
        _pfNo.text = st.pfNumber ?? '';
        _esiNo.text = st.esiNumber ?? '';
        _ptState.text = st.ptState ?? '';
        _ptAmount.text = (st.ptMonthlyPaise ~/ 100).toString();
        _ptMin.text = st.ptMinGrossPaise == 0 ? '' : (st.ptMinGrossPaise ~/ 100).toString();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final st = await ref.read(companyApiProvider).updateStatutory({
        'pfEnabled': _pf,
        'pfNumber': _pfNo.text.trim().isEmpty ? null : _pfNo.text.trim(),
        'basicPercent': _basic,
        'esiEnabled': _esi,
        'esiNumber': _esiNo.text.trim().isEmpty ? null : _esiNo.text.trim(),
        'ptEnabled': _pt,
        'ptState': _ptState.text.trim().isEmpty ? null : _ptState.text.trim(),
        'ptMonthlyPaise': ((int.tryParse(_ptAmount.text.trim()) ?? 0) * 100).clamp(0, 250000),
        'ptMinGrossPaise': (int.tryParse(_ptMin.text.trim()) ?? 0) * 100,
      });
      if (!mounted) return;
      setState(() => _st = st);
      showSnack(context, context.s.saved);
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    Widget section({
      required Key key,
      required String title,
      required String example,
      required bool value,
      required ValueChanged<bool> onChanged,
      List<Widget> fields = const [],
    }) => Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: key,
              contentPadding: EdgeInsets.zero,
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              value: value,
              onChanged: onChanged,
            ),
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: AppColors.whyBg, borderRadius: BorderRadius.circular(10)),
              child: Text(example, style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.35)),
            ),
            if (value) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(children: fields),
              ),
            ],
          ],
        ),
      ),
    );
    Widget field(TextEditingController c, String label, {Key? key, TextInputType? type}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: key,
        controller: c,
        keyboardType: type,
        decoration: InputDecoration(labelText: label),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(s.statutoryBi.text)),
      bottomNavigationBar: _st == null
          ? null
          : StickySaveBar(buttonKey: const Key('saveStatutory'), label: s.save, onPressed: _saving ? null : _save),
      body: _st == null
          ? (_error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView())
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(s.statutoryIntro, style: const TextStyle(color: AppColors.muted, height: 1.4)),
                ),
                section(
                  key: const Key('pfSwitch'),
                  title: s.pfTitle,
                  example: s.pfExample,
                  value: _pf,
                  onChanged: (v) => setState(() => _pf = v),
                  fields: [
                    field(_pfNo, s.pfNumberLabel, key: const Key('pfNumber')),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(s.basicPercentLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final p in const [40, 50, 60, 100])
                          ChoiceChip(
                            label: Text('$p%'),
                            selected: _basic == p,
                            onSelected: (_) => setState(() => _basic = p),
                          ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(s.basicPercentHint, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    ),
                  ],
                ),
                section(
                  key: const Key('esiSwitch'),
                  title: s.esiTitle,
                  example: s.esiExample,
                  value: _esi,
                  onChanged: (v) => setState(() => _esi = v),
                  fields: [field(_esiNo, s.esiNumberLabel, key: const Key('esiNumber'))],
                ),
                section(
                  key: const Key('ptSwitch'),
                  title: s.ptTitle,
                  example: s.ptExample,
                  value: _pt,
                  onChanged: (v) => setState(() => _pt = v),
                  fields: [
                    field(_ptState, s.ptStateLabel),
                    field(_ptAmount, s.ptAmountLabel, key: const Key('ptAmount'), type: TextInputType.number),
                    field(_ptMin, s.ptMinLabel, type: TextInputType.number),
                    if ((int.tryParse(_ptAmount.text) ?? 0) > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Money.format((int.tryParse(_ptAmount.text) ?? 0) * 100),
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}
