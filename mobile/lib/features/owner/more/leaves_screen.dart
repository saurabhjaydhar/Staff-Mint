import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../home/owner_home_screen.dart';
import '../providers/owner_providers.dart';

class LeavesScreen extends ConsumerStatefulWidget {
  const LeavesScreen({super.key});

  @override
  ConsumerState<LeavesScreen> createState() => _LeavesScreenState();
}

class _LeavesScreenState extends ConsumerState<LeavesScreen> {
  bool _pendingOnly = true;
  final Set<String> _busy = {};

  String? get _status => _pendingOnly ? 'pending' : null;

  Future<void> _decide(Leave l, bool approve) async {
    setState(() => _busy.add(l.id));
    final s = context.s;
    final ok = await runGuarded(
      context,
      () => ref.read(leaveApiProvider).decide(l.id, approve: approve),
      success: approve ? s.approved : s.rejected,
    );
    if (ok) invalidateAttendance(ref);
    if (mounted) setState(() => _busy.remove(l.id));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final leaves = ref.watch(leavesProvider(_status));
    return Scaffold(
      appBar: AppBar(title: Text(s.leaveRequests)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(s.pending)),
                ButtonSegment(value: false, label: Text(s.all)),
              ],
              selected: {_pendingOnly},
              onSelectionChanged: (v) => setState(() => _pendingOnly = v.first),
            ),
          ),
          Expanded(
            child: AsyncBody<List<Leave>>(
              value: leaves,
              onRetry: () => ref.invalidate(leavesProvider(_status)),
              data: (list) => RefreshableList(
                onRefresh: () => ref.refresh(leavesProvider(_status).future),
                children: [
                  if (list.isEmpty) EmptyView(message: s.noLeaveRequests, icon: Icons.beach_access_outlined),
                  for (final l in list)
                    LeaveDecisionCard(leave: l, busy: _busy.contains(l.id), onDecide: (a) => _decide(l, a), s: s),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
