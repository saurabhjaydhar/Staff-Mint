import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/providers.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/track_map.dart';

final liveStaffProvider = FutureProvider.autoDispose<List<LiveStaff>>((ref) => ref.watch(trackingApiProvider).live());

/// (employeeId or null for "my own", date)
final trackDayProvider = FutureProvider.autoDispose.family<TrackDay, (String?, String)>(
  (ref, k) => ref.watch(trackingApiProvider).day(k.$2, employeeId: k.$1),
);

String km(int m) => (m / 1000).toStringAsFixed(m < 10000 ? 1 : 0);

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.length == 1 ? parts[0].substring(0, 1) : '${parts[0][0]}${parts[1][0]}').toUpperCase();
}

Color statusColor(String status) => switch (status) {
  'live' => AppColors.mint,
  'recent' => AppColors.amber,
  _ => AppColors.muted,
};

String ago(S s, DateTime at) {
  final m = DateTime.now().difference(at).inMinutes;
  return m < 60 ? s.minAgo(m) : s.hoursAgo(m ~/ 60);
}

/// Owner: where field staff are now (initials on the map, green under 5 minutes, amber under 15), and each one's day.
class FieldStaffMapScreen extends ConsumerStatefulWidget {
  const FieldStaffMapScreen({super.key});

  @override
  ConsumerState<FieldStaffMapScreen> createState() => _FieldStaffMapScreenState();
}

class _FieldStaffMapScreenState extends ConsumerState<FieldStaffMapScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Keep it fresh while it's open.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => ref.invalidate(liveStaffProvider));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final live = ref.watch(liveStaffProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.fieldMapTitle)),
      body: AsyncBody<List<LiveStaff>>(
        value: live,
        onRetry: () => ref.invalidate(liveStaffProvider),
        data: (list) {
          if (list.isEmpty) return EmptyView(icon: Icons.share_location_rounded, message: s.fieldNone);
          void open(LiveStaff p) => openTrackDay(context, employeeId: p.employeeId, name: p.name);
          return RefreshableList(
            onRefresh: () => ref.refresh(liveStaffProvider.future),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              TrackMap(
                key: const Key('liveMap'),
                markers: [
                  for (final p in list.where((p) => p.onMap))
                    TrackMarker(
                      point: LatLng(p.lat!, p.lng!),
                      label: _initials(p.name),
                      color: statusColor(p.status),
                      title: p.name,
                      onTap: () => open(p),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final p in list)
                      ListTile(
                        key: Key('live_${p.employeeId}'),
                        leading: CircleAvatar(
                          backgroundColor: statusColor(p.status),
                          foregroundColor: Colors.white,
                          child: Text(_initials(p.name), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          [
                            if (p.lastPingAt != null && p.status != 'waiting_consent') ago(s, p.lastPingAt!),
                            if (s.liveStatus(p.status).isNotEmpty) s.liveStatus(p.status),
                            if (p.near != null) s.nearPlace(p.near!),
                            if (p.distanceM > 0) s.kmShort(km(p.distanceM)),
                          ].join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => open(p),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// [employeeId] null: the staff member's own route.
Future<void> openTrackDay(BuildContext context, {String? employeeId, required String name}) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => TrackDayScreen(employeeId: employeeId, name: name),
      ),
    );

/// One person's day: the route, stops (10+ minutes in one place) with how long, check-in/out, and the km.
class TrackDayScreen extends ConsumerStatefulWidget {
  const TrackDayScreen({super.key, this.employeeId, required this.name});
  final String? employeeId;
  final String name;

  @override
  ConsumerState<TrackDayScreen> createState() => _TrackDayScreenState();
}

class _TrackDayScreenState extends ConsumerState<TrackDayScreen> {
  DateTime _day = Dates.today();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final date = Dates.toApiDate(_day);
    final day = ref.watch(trackDayProvider((widget.employeeId, date)));
    final isToday = Dates.toApiDate(Dates.today()) == date;
    return Scaffold(
      appBar: AppBar(title: Text(widget.employeeId == null ? s.myRoute : widget.name)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              children: [
                IconButton(
                  key: const Key('dayPrev'),
                  onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    Dates.pretty(_day, s.languageCode),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                IconButton(
                  key: const Key('dayNext'),
                  onPressed: isToday ? null : () => setState(() => _day = _day.add(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody<TrackDay>(
              value: day,
              onRetry: () => ref.invalidate(trackDayProvider((widget.employeeId, date))),
              data: (d) => _body(s, d, date),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(S s, TrackDay d, String date) {
    final markers = <TrackMarker>[
      for (final p in d.punches)
        TrackMarker(
          point: LatLng(p.at.lat, p.at.lng),
          label: p.type == 'in' ? '▶' : '■',
          color: p.type == 'in' ? AppColors.mint : AppColors.red,
          title: '${p.type == 'in' ? s.checkedInHere : s.checkedOutHere} ${Dates.time(p.at.at, s.languageCode)}',
        ),
      for (final (i, st) in d.stops.indexed)
        TrackMarker(
          point: LatLng(st.lat, st.lng),
          label: '${i + 1}',
          color: AppColors.amberDark,
          title: st.place ?? '${i + 1}',
        ),
    ];
    return RefreshableList(
      onRefresh: () => ref.refresh(trackDayProvider((widget.employeeId, date)).future),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        if (d.route.isEmpty && d.punches.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: EmptyView(icon: Icons.route_rounded, message: s.noRouteYet),
          )
        else ...[
          TrackMap(key: const Key('dayMap'), route: [for (final p in d.route) LatLng(p.lat, p.lng)], markers: markers),
          const SizedBox(height: 12),
          Row(
            children: [
              _Figure(key: const Key('dayKm'), label: s.dayKm, value: s.kmShort(km(d.distanceM))),
              const SizedBox(width: 10),
              _Figure(key: const Key('dayStops'), label: s.dayStops, value: '${d.stops.length}'),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                // Check-in, stops and check-out in the order they happened.
                for (final e in _timeline(d))
                  switch (e) {
                    (final DateTime at, final ({String type, TrackPoint at}) p) => ListTile(
                      leading: Icon(
                        p.type == 'in' ? Icons.login_rounded : Icons.logout_rounded,
                        color: p.type == 'in' ? AppColors.mintDark : AppColors.red,
                      ),
                      title: Text(
                        p.type == 'in' ? s.checkedInHere : s.checkedOutHere,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: Text(Dates.time(at, s.languageCode)),
                    ),
                    (_, final (int, TrackStop) st) => ListTile(
                      key: Key('stop_${st.$1}'),
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.amberDark,
                        foregroundColor: Colors.white,
                        child: Text('${st.$1 + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                      title: Text(
                        st.$2.place ?? s.stopN(st.$1 + 1),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        s.stopLine(
                          Dates.time(st.$2.from, s.languageCode),
                          Dates.time(st.$2.to, s.languageCode),
                          st.$2.minutes,
                        ),
                      ),
                    ),
                    _ => const SizedBox.shrink(),
                  },
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// (time, punch) and (time, (index, stop)), sorted by time.
List<(DateTime, Object)> _timeline(TrackDay d) {
  final items = <(DateTime, Object)>[
    for (final p in d.punches) (p.at.at, p),
    for (final (i, st) in d.stops.indexed) (st.from, (i, st)),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return items;
}

class _Figure extends StatelessWidget {
  const _Figure({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.mintFaint, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        ],
      ),
    ),
  );
}
