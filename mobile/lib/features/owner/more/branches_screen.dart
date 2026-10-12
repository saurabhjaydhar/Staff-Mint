import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/providers.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/location_picker.dart';
import '../providers/owner_providers.dart';

/// Branch geofence: pin + radius per branch.
class BranchesScreen extends ConsumerWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final branches = ref.watch(branchesProvider);
    Future<void> edit([Branch? b]) async {
      final changed = await Navigator.of(
        context,
      ).push<bool>(MaterialPageRoute(builder: (_) => BranchEditScreen(branch: b)));
      if (changed == true) ref.invalidate(branchesProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.geofence),
        actions: [
          IconButton(tooltip: s.addBranch, icon: const Icon(Icons.add_location_alt_rounded), onPressed: () => edit()),
        ],
      ),
      body: AsyncBody<List<Branch>>(
        value: branches,
        onRetry: () => ref.invalidate(branchesProvider),
        data: (list) => RefreshableList(
          onRefresh: () => ref.refresh(branchesProvider.future),
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(s.geofenceHint)),
            if (list.isEmpty) EmptyView(message: s.nothingHere),
            for (final b in list)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront_rounded, size: 30),
                  title: Text(b.name),
                  subtitle: Text(
                    [s.radiusLabel(b.radiusM), if (b.location?.address != null) b.location!.address!].join(' · '),
                  ),
                  trailing: const Icon(Icons.edit_location_alt_rounded),
                  onTap: () => edit(b),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BranchEditScreen extends ConsumerStatefulWidget {
  const BranchEditScreen({super.key, this.branch});
  final Branch? branch;

  @override
  ConsumerState<BranchEditScreen> createState() => _BranchEditScreenState();
}

class _BranchEditScreenState extends ConsumerState<BranchEditScreen> {
  late final _name = TextEditingController(text: widget.branch?.name ?? '');
  late final _address = TextEditingController(text: widget.branch?.location?.address ?? '');
  late LatLng? _pin = widget.branch?.location == null
      ? null
      : LatLng(widget.branch!.location!.lat, widget.branch!.location!.lng);
  late double _radius = (widget.branch?.radiusM ?? 100).toDouble();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.s;
    if (_name.text.trim().isEmpty || _pin == null) {
      showSnack(context, _pin == null ? s.pinRequired : s.required, error: true);
      return;
    }
    final location = GeoPoint(lat: _pin!.latitude, lng: _pin!.longitude, address: _address.text.trim());
    setState(() => _busy = true);
    final api = ref.read(companyApiProvider);
    final ok = await runGuarded(context, () async {
      if (widget.branch == null) {
        await api.createBranch(name: _name.text.trim(), location: location, radiusM: _radius.round());
      } else {
        await api.updateBranch(widget.branch!.id, {
          'name': _name.text.trim(),
          'location': location.toJson(),
          'radiusM': _radius.round(),
        });
      }
    }, success: s.saved);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(widget.branch == null ? s.addBranch : widget.branch!.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: s.branchName),
          ),
          const SizedBox(height: 12),
          LocationPicker(
            value: _pin,
            radiusM: _radius,
            address: _address.text,
            onChanged: (p) => setState(() => _pin = p),
            onAddress: (a) => setState(() => _address.text = a),
          ),
          const SizedBox(height: 12),
          Text(s.radiusLabel(_radius.round()), style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _radius.clamp(25, 1000),
            min: 25,
            max: 1000,
            divisions: 39,
            label: '${_radius.round()} m',
            onChanged: (v) => setState(() => _radius = v),
          ),
          TextField(
            controller: _address,
            decoration: InputDecoration(labelText: s.addressOptional),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _save, child: Text(s.save)),
        ],
      ),
    );
  }
}
