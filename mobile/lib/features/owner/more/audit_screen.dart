import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';

/// History of changes in plain words: "Raju: 1 Oct set to Absent · by Saurabh · 10:42 AM",
/// grouped by day, with a filter per kind of change. Tap a row to see what changed.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  static const _pageSize = 50;
  static const _filters = [null, 'attendance', 'leave', 'salary', 'staff', 'settings', 'team'];
  final List<AuditLog> _items = [];
  String? _category;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _hasMore = true;
      }
    });
    final category = _category;
    try {
      final before = _items.isEmpty ? null : _items.last.at?.toUtc().toIso8601String();
      final page = await ref.read(auditApiProvider).list(limit: _pageSize, before: before, category: category);
      if (!mounted || category != _category) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length >= _pageSize;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted && category == _category) setState(() => _loading = false);
    }
  }

  void _setFilter(String? c) {
    if (c == _category) return;
    setState(() => _category = c);
    _load(reset: true);
  }

  String _dayLabel(S s, DateTime d) {
    final today = Dates.today();
    final day = DateTime(d.year, d.month, d.day);
    final ago = today.difference(day).inDays;
    if (ago == 0) return s.relToday;
    if (ago == 1) return s.relYesterday;
    return Dates.weekdayShort(day, s.languageCode);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    // Rows with a day header whenever the day changes.
    final rows = <Widget>[];
    String? lastDay;
    for (final a in _items) {
      final local = a.at?.toLocal();
      final day = local == null ? '' : _dayLabel(s, local);
      if (day != lastDay) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(
              day,
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.muted),
            ),
          ),
        );
        lastDay = day;
      }
      rows.add(_HistoryTile(log: a));
    }
    return Scaffold(
      appBar: AppBar(title: Text(s.historyOfChanges)),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              children: [
                for (final c in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('historyFilter_${c ?? 'all'}'),
                      label: Text(s.historyFilter(c ?? 'all')),
                      selected: _category == c,
                      onSelected: (_) => _setFilter(c),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _items.isEmpty && _error != null
                ? ErrorView(error: _error!, onRetry: () => _load(reset: true))
                : _items.isEmpty && _loading
                ? const LoadingView()
                : RefreshableList(
                    onRefresh: () => _load(reset: true),
                    children: [
                      if (_items.isEmpty)
                        EmptyView(
                          message: _category == null ? s.noAuditLogs : s.historyNothingHere,
                          icon: Icons.history_rounded,
                        ),
                      if (_items.isNotEmpty && _category == null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                          child: Text(s.historyHint, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                        ),
                      ...rows,
                      if (_hasMore && _items.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: OutlinedButton(
                            onPressed: _loading ? null : _load,
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.5),
                                  )
                                : Text(s.loadMore),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatefulWidget {
  const _HistoryTile({required this.log});
  final AuditLog log;

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _open = false;

  static (IconData, Color, Color) _look(String category) => switch (category) {
    'attendance' => (Icons.event_available_rounded, AppColors.mintDark, AppColors.mintLight),
    'leave' => (Icons.beach_access_rounded, AppColors.indigo, AppColors.indigoLight),
    'salary' => (Icons.currency_rupee_rounded, AppColors.amberDark, AppColors.amberLight),
    'staff' => (Icons.person_rounded, AppColors.mintDark, AppColors.mintFaint),
    'settings' => (Icons.tune_rounded, AppColors.ink, AppColors.mutedLight),
    'team' => (Icons.key_rounded, AppColors.orange, AppColors.orangeLight),
    'billing' => (Icons.workspace_premium_rounded, AppColors.indigo, AppColors.indigoLight),
    _ => (Icons.history_rounded, AppColors.muted, AppColors.mutedLight),
  };

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final a = widget.log;
    final (icon, fg, bg) = _look(a.category);
    final who = a.channel == 'system' ? s.historyAutomatic : a.actorName;
    final meta = [
      s.historyBy(who),
      if (s.historyVia(a.channel).isNotEmpty && a.channel != 'system') s.historyVia(a.channel),
      if (a.at != null) Dates.time(a.at!, s.languageCode),
    ].join(' · ');
    final canOpen = a.changes.isNotEmpty;
    return Card(
      key: Key('history_${a.id}'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: InkWell(
        borderRadius: AppTheme.radius,
        onTap: canOpen ? () => setState(() => _open = !_open) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, color: fg, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.text ?? s.historyChanged,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, height: 1.3),
                    ),
                    const SizedBox(height: 2),
                    Text(meta, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                    if (_open)
                      Container(
                        key: Key('historyChanges_${a.id}'),
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.whyBg, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final c in a.changes)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '${c.label}: ',
                                        style: const TextStyle(color: AppColors.muted),
                                      ),
                                      if (c.from != null) ...[
                                        TextSpan(
                                          text: c.from,
                                          style: const TextStyle(decoration: TextDecoration.lineThrough),
                                        ),
                                        const TextSpan(text: '  →  '),
                                      ],
                                      TextSpan(
                                        text: c.to ?? '—',
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (canOpen) Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
