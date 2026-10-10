import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/services/company_api.dart';
import '../../core/i18n/strings.dart';
import '../../core/models/models.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bilingual.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/location_picker.dart';
import '../../core/widgets/pickers.dart';
import '../auth/auth_controller.dart';
import 'who_are_you.dart';

const businessTypes = ['pharmacy', 'clinic', 'salon', 'restaurant', 'shop', 'office', 'other'];

/// Usual opening hours per business type, pre-filled in the timings step.
const businessHours = <String, (String, String)>{
  'pharmacy': ('09:00', '21:00'),
  'clinic': ('10:00', '20:00'),
  'salon': ('10:00', '21:00'),
  'restaurant': ('11:00', '23:00'),
  'shop': ('09:00', '21:00'),
  'office': ('09:30', '18:30'),
  'other': ('09:00', '19:00'),
};

const businessIcons = <String, IconData>{
  'pharmacy': Icons.local_pharmacy_rounded,
  'clinic': Icons.medical_services_rounded,
  'salon': Icons.content_cut_rounded,
  'restaurant': Icons.restaurant_rounded,
  'shop': Icons.storefront_rounded,
  'office': Icons.business_center_rounded,
  'other': Icons.category_rounded,
};

/// Company setup: 4 screens here + the "Add staff" screen = 5 (PRD F1).
///
/// [another]: a signed-in person (owner, staff or accountant elsewhere)
/// creating one more business. Skips "who are you?" and can be left with back.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key, this.another = false});
  final bool another;

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  static const totalSteps = 5;
  int _step = 0;

  /// null: not asked yet · owner · staff
  late String? _who = widget.another ? 'owner' : null;
  bool _busy = false;

  void _back() {
    if (_step > 0) return setState(() => _step--);
    if (widget.another) {
      context.canPop() ? context.pop() : context.go(Routes.splash);
      return;
    }
    setState(() => _who = null);
  }

  final _name = TextEditingController();
  final _address = TextEditingController();
  String _type = 'shop';
  LatLng? _pin;
  String _open = businessHours['shop']!.$1;
  String _close = businessHours['shop']!.$2;
  bool _timesTouched = false;
  List<int> _weeklyOff = [0];

  void _setType(String t) => setState(() {
    _type = t;
    if (!_timesTouched) {
      final (open, close) = businessHours[t] ?? businessHours['other']!;
      _open = open;
      _close = close;
    }
  });

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
      // Router forwards /setup → /setup/staff once the company exists; another
      // business starts at /accounts/new, so move on to the staff step here.
      if (widget.another && mounted) context.go(Routes.setupStaff);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final locked = ref.watch(authControllerProvider.select((x) => x.blockedAccounts));
    if (_who == null && !widget.another && locked.isNotEmpty) {
      return DeviceLockedView(onOwnBusiness: () => setState(() => _who = 'owner'));
    }
    if (_who == null) {
      return WhoAreYouView(
        onOwner: () => setState(() => _who = 'owner'),
        onStaff: () => setState(() => _who = 'staff'),
      );
    }
    if (_who == 'staff') return WaitingForEmployerView(onBack: () => setState(() => _who = null));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
          title: Text(widget.another && _step == 0 ? s.newBusiness : s.setupStep(_step + 1, totalSteps)),
          actions: const [LangPill(), SizedBox(width: 8)],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(14),
            child: SetupProgress(step: _step, total: totalSteps),
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
      Text(t, style: Theme.of(context).textTheme.headlineSmall),
      if (sub != null) ...[
        const SizedBox(height: 8),
        Text(sub, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted)),
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
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.05,
              children: [
                for (final t in businessTypes)
                  _TypeTile(
                    icon: businessIcons[t]!,
                    label: s.businessTypeLabel(t),
                    selected: _type == t,
                    onTap: () => _setType(t),
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
            LocationPicker(value: _pin, radiusM: 100, autoLocate: true, onChanged: (p) => setState(() => _pin = p)),
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
            if (!_timesTouched)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.mintLight, borderRadius: AppTheme.radius),
                child: Row(
                  children: [
                    Icon(businessIcons[_type], color: AppColors.mintDark),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.timingsPrefilled(s.businessTypeLabel(_type)))),
                  ],
                ),
              ),
            TimeField(
              label: s.openingTime,
              value: _open,
              onChanged: (v) => setState(() {
                _open = v;
                _timesTouched = true;
              }),
            ),
            const SizedBox(height: 16),
            TimeField(
              label: s.closingTime,
              value: _close,
              onChanged: (v) => setState(() {
                _close = v;
                _timesTouched = true;
              }),
            ),
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

class _TypeTile extends StatelessWidget {
  const _TypeTile({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? AppColors.mintLight : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.radius,
        side: BorderSide(color: selected ? AppColors.mint : AppColors.line, width: selected ? 2 : 1.5),
      ),
      child: InkWell(
        borderRadius: AppTheme.radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: selected ? AppColors.mintDark : AppColors.ink),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: selected ? AppColors.mintDark : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Five-segment setup progress (shared with the add-staff step).
class SetupProgress extends StatelessWidget {
  const SetupProgress({super.key, required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i <= step ? AppColors.mint : AppColors.line,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
