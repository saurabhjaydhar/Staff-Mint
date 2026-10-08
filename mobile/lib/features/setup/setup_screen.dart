import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/services/company_api.dart';
import '../../core/i18n/locale_provider.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/location_picker.dart';
import '../../core/widgets/pickers.dart';
import '../auth/auth_controller.dart';

const businessTypes = ['pharmacy', 'clinic', 'salon', 'restaurant', 'shop', 'office', 'other'];

const _businessIcons = <String, IconData>{
  'pharmacy': Icons.local_pharmacy_rounded,
  'clinic': Icons.medical_services_rounded,
  'salon': Icons.content_cut_rounded,
  'restaurant': Icons.restaurant_rounded,
  'shop': Icons.storefront_rounded,
  'office': Icons.business_center_rounded,
  'other': Icons.category_rounded,
};

/// Company setup: 4 screens here + the "Add staff" screen = 5 (PRD F1).
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  static const totalSteps = 5;
  int _step = 0;
  bool _busy = false;

  final _name = TextEditingController();
  final _address = TextEditingController();
  String _type = 'shop';
  LatLng? _pin;
  String _open = '09:00';
  String _close = '19:00';
  List<int> _weeklyOff = [0];

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _name.text.trim().length >= 2;
      case 1:
        return _pin != null;
      default:
        return true;
    }
  }

  Future<void> _next() async {
    final s = context.s;
    if (_step == 1 && _pin == null) {
      showSnack(context, s.pinRequired, error: true);
      return;
    }
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .createCompany(
            CreateCompanyRequest(
              name: _name.text.trim(),
              businessType: _type,
              location: GeoPoint(lat: _pin!.latitude, lng: _pin!.longitude, address: _address.text.trim()),
              openingTime: _open,
              closingTime: _close,
              weeklyOff: _weeklyOff,
            ),
          );
      // Router forwards /setup → /setup/staff once the company exists.
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final lang = ref.watch(localeProvider);
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _step > 0
              ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _step--))
              : null,
          title: Text(s.setupStep(_step + 1, totalSteps)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: () => ref.read(localeProvider.notifier).toggle(),
                child: Text(lang == 'hi' ? s.english : s.hindi),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(value: (_step + 1) / totalSteps),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(padding: const EdgeInsets.all(20), children: [_buildStep(context)]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy || !_canContinue ? null : _next,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : Text(_step == 3 ? s.createBusiness : s.next),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(String t, [String? sub]) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(t, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      if (sub != null) ...[
        const SizedBox(height: 8),
        Text(sub, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54)),
      ],
      const SizedBox(height: 20),
    ],
  );

  Widget _buildStep(BuildContext context) {
    final s = context.s;
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(s.setupBusinessTitle),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: s.businessName, hintText: s.businessNameHint),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            Text(s.businessType, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final t in businessTypes)
                  ChoiceChip(
                    avatar: Icon(_businessIcons[t], size: 20),
                    label: Text(s.businessTypeLabel(t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(s.setupLocationTitle, s.setupLocationHint),
            LocationPicker(value: _pin, radiusM: 100, onChanged: (p) => setState(() => _pin = p)),
            const SizedBox(height: 16),
            TextField(
              controller: _address,
              decoration: InputDecoration(labelText: s.addressOptional),
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(s.setupTimingTitle, s.setupTimingHint),
            TimeField(label: s.openingTime, value: _open, onChanged: (v) => setState(() => _open = v)),
            const SizedBox(height: 16),
            TimeField(label: s.closingTime, value: _close, onChanged: (v) => setState(() => _close = v)),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(s.setupWeeklyOffTitle, s.setupWeeklyOffHint),
            WeekdayChips(selected: _weeklyOff, onChanged: (v) => setState(() => _weeklyOff = v)),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _weeklyOff.isEmpty,
              title: Text(s.noWeeklyOff),
              onChanged: (v) => setState(() => _weeklyOff = v == true ? [] : [0]),
            ),
          ],
        );
    }
  }
}
