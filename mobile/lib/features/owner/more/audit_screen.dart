import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/common.dart';

/// Who changed what, when, from which channel. Paginates with `before`.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  static const _pageSize = 50;
  final List<AuditLog> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _hasMore = true;
      }
    });
    try {
      final before = _items.isEmpty ? null : (_items.last.at?.toUtc().toIso8601String() ?? _items.last.id);
      final page = await ref.read(auditApiProvider).list(limit: _pageSize, before: before);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length >= _pageSize;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _pretty(Object? v) {
    if (v == null) return '—';
    if (v is Map || v is List) return const JsonEncoder.withIndent('  ').convert(v);
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.auditLog)),
      body: _items.isEmpty && _error != null
          ? ErrorView(error: _error!, onRetry: () => _load(reset: true))
          : _items.isEmpty && _loading
          ? const LoadingView()
          : RefreshableList(
              onRefresh: () => _load(reset: true),
              children: [
                if (_items.isEmpty) EmptyView(message: s.noAuditLogs, icon: Icons.history_rounded),
                for (final a in _items)
                  Card(
                    child: ExpansionTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: AppColors.mutedLight, borderRadius: BorderRadius.circular(12)),
                        child: Icon(_channelIcon(a.channel), color: AppColors.ink, size: 20),
                      ),
                      title: Text('${a.action} · ${a.entity}'),
                      subtitle: Text(
                        [
                          s.byActor(a.actorName, a.channel),
                          if (a.at != null)
                            '${Dates.pretty(a.at!.toLocal(), s.languageCode)} ${Dates.time(a.at!, s.languageCode)}',
                        ].join('\n'),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(s.before, style: const TextStyle(fontWeight: FontWeight.w700)),
                        SelectableText(
                          _pretty(a.before),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Text(s.after, style: const TextStyle(fontWeight: FontWeight.w700)),
                        SelectableText(_pretty(a.after), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                      ],
                    ),
                  ),
                if (_hasMore && _items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton(
                      onPressed: _loading ? null : _load,
                      child: _loading
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : Text(s.loadMore),
                    ),
                  ),
              ],
            ),
    );
  }

  IconData _channelIcon(String c) {
    switch (c) {
      case 'assistant':
        return Icons.auto_awesome_rounded;
      case 'whatsapp':
        return Icons.chat_rounded;
      case 'web':
        return Icons.computer_rounded;
      case 'system':
        return Icons.settings_suggest_rounded;
      case 'import':
        return Icons.upload_file_rounded;
      default:
        return Icons.phone_android_rounded;
    }
  }
}
