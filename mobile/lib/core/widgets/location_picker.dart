import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../api/providers.dart';
import '../api/services/geo_api.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../utils/location.dart';
import 'common.dart';
import 'shop_map.dart';

/// What the full-screen picker returns.
class PickedLocation {
  const PickedLocation(this.point, this.address);
  final LatLng point;
  final String? address;
}

/// Shop location on a form: a small map preview with the circle, the address, and
/// "Change on map" (full-screen picker with search) / "Use my current location".
class LocationPicker extends ConsumerStatefulWidget {
  const LocationPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.onAddress,
    this.address,
    this.radiusM,
    this.height = 200,
    this.autoLocate = false,
  });

  final LatLng? value;
  final ValueChanged<LatLng> onChanged;

  /// Address found for the pin (from search or the map); the form fills its address field.
  final ValueChanged<String>? onAddress;
  final String? address;
  final double? radiusM;
  final double height;

  /// Try "use my current location" as soon as the picker appears (when no pin is set yet).
  final bool autoLocate;

  /// Centre of India — used until a pin is placed.
  static const fallbackCenter = LatLng(22.9734, 78.6569);

  @override
  ConsumerState<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends ConsumerState<LocationPicker> {
  bool _locating = false;
  bool _mapFailed = false;

  /// Bumped to rebuild the preview map at a new pin.
  int _version = 0;

  @override
  void initState() {
    super.initState();
    if (widget.autoLocate && widget.value == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useCurrent(quiet: true));
    }
  }

  void _set(LatLng p, String? address) {
    widget.onChanged(p);
    if (address != null && address.isNotEmpty) widget.onAddress?.call(address);
    setState(() => _version++);
  }

  Future<void> _useCurrent({bool quiet = false}) async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService.current();
      final p = LatLng(pos.latitude, pos.longitude);
      _set(p, null);
      unawaited(_lookUpAddress(p));
    } on LocationException catch (e) {
      if (mounted && !quiet) {
        showSnack(
          context,
          e.serviceDisabled ? context.s.locationServiceOff : context.s.locationPermissionDenied,
          error: true,
        );
      }
    } catch (_) {
      if (mounted && !quiet) showSnack(context, context.s.genericError, error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _lookUpAddress(LatLng p) async {
    try {
      final a = await ref.read(geoApiProvider).reverse(p.latitude, p.longitude, lang: context.s.languageCode);
      if (mounted && a != null && a.isNotEmpty) widget.onAddress?.call(a);
    } catch (_) {
      // The address is a convenience; the pin is what matters.
    }
  }

  Future<void> _openMap() async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MapPickerScreen(initial: widget.value, radiusM: widget.radiusM),
      ),
    );
    if (picked != null && mounted) _set(picked.point, picked.address);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final pin = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: AppTheme.radius,
          child: SizedBox(
            height: widget.height,
            child: pin == null
                ? _EmptyPreview(onTap: _openMap)
                : Stack(
                    children: [
                      IgnorePointer(
                        child: ShopMap(
                          key: ValueKey(_version),
                          initialCenter: pin,
                          radiusM: widget.radiusM,
                          interactive: false,
                          onLoadError: () => setState(() => _mapFailed = true),
                        ),
                      ),
                      const CentrePin(size: 40),
                      Positioned.fill(
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(key: const Key('mapPreview'), onTap: _openMap),
                        ),
                      ),
                      if (_locating)
                        Positioned(top: 10, left: 10, right: 10, child: _Chip(text: s.findingLocation))
                      else if (_mapFailed)
                        Positioned(
                          top: 10,
                          left: 10,
                          right: 10,
                          child: _Chip(text: s.mapLoadFailed, color: AppColors.red),
                        ),
                    ],
                  ),
          ),
        ),
        if (pin != null && (widget.address ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_outlined, size: 18, color: AppColors.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(widget.address!, style: const TextStyle(color: AppColors.muted)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('openMapPicker'),
                onPressed: _openMap,
                icon: const Icon(Icons.map_outlined),
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(pin == null ? s.findOnMap : s.changeOnMap)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _locating ? null : () => _useCurrent(),
                icon: _locating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded),
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(s.useMyLocation)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Material(
      color: AppColors.mintFaint,
      child: InkWell(
        key: const Key('mapPreview'),
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_location_alt_rounded, size: 44, color: AppColors.mintDark),
                const SizedBox(height: 8),
                Text(s.setShopLocation, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  s.setShopLocationHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.text, this.color = AppColors.ink});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 13.5),
      ),
    ),
  );
}

/// Full-screen picker like Google Maps: search on top, the pin fixed in the middle (move the
/// map under it), Map / Satellite, my location, and the address of the spot under the pin.
class MapPickerScreen extends ConsumerStatefulWidget {
  const MapPickerScreen({super.key, this.initial, this.radiusM});
  final LatLng? initial;
  final double? radiusM;

  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  final _map = ShopMapController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  late LatLng _center = widget.initial ?? LocationPicker.fallbackCenter;
  LatLng? _me;
  String? _address;
  bool _addressLoading = false;
  bool _satellite = false;
  bool _locating = false;
  bool _mapFailed = false;
  List<GeoPlace>? _results;
  bool _searching = false;
  Timer? _searchDebounce;
  Timer? _addressDebounce;

  /// Address already known for this exact point (picked from search), so no lookup is needed.
  LatLng? _addressFor;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToMe(quiet: true));
    } else {
      _scheduleAddress(_center);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _addressDebounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _lang => context.s.languageCode;

  Future<void> _goToMe({bool quiet = false}) async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService.current();
      final p = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _me = p);
      _map.moveTo(p);
    } on LocationException catch (e) {
      if (mounted && !quiet) {
        showSnack(
          context,
          e.serviceDisabled ? context.s.locationServiceOff : context.s.locationPermissionDenied,
          error: true,
        );
      }
    } catch (_) {
      if (mounted && !quiet) showSnack(context, context.s.genericError, error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    if (text.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _runSearch(text.trim()));
  }

  Future<void> _runSearch(String q) async {
    setState(() => _searching = true);
    try {
      final hasPin = widget.initial != null || _me != null;
      final found = await ref
          .read(geoApiProvider)
          .search(q, lat: hasPin ? _center.latitude : null, lng: hasPin ? _center.longitude : null, lang: _lang);
      if (mounted && _search.text.trim() == q) setState(() => _results = found);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pickResult(GeoPlace p) {
    final point = LatLng(p.lat, p.lng);
    _searchFocus.unfocus();
    setState(() {
      _results = null;
      _search.text = p.name;
      _address = [p.name, p.address].where((x) => x.isNotEmpty).toSet().join(', ');
      _addressFor = point;
      _center = point;
    });
    _map.moveTo(point);
  }

  void _scheduleAddress(LatLng c) {
    _addressDebounce?.cancel();
    if (_addressFor != null && const Distance().as(LengthUnit.Meter, _addressFor!, c) < 15) return;
    _addressFor = null;
    setState(() => _addressLoading = true);
    _addressDebounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final a = await ref.read(geoApiProvider).reverse(c.latitude, c.longitude, lang: _lang);
        if (mounted && _center == c) setState(() => _address = a);
      } catch (_) {
        if (mounted && _center == c) setState(() => _address = null);
      } finally {
        if (mounted && _center == c) setState(() => _addressLoading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final distance = _me == null ? null : const Distance().as(LengthUnit.Meter, _me!, _center).round();
    final inside = distance != null && widget.radiusM != null && distance <= widget.radiusM!;
    return Scaffold(
      appBar: AppBar(title: Text(s.shopLocationTitle)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                ShopMap(
                  initialCenter: _center,
                  initialZoom: widget.initial == null ? 5 : 17,
                  radiusM: widget.radiusM,
                  satellite: _satellite,
                  showMyLocation: _me != null,
                  controller: _map,
                  onMove: (c) => setState(() => _center = c),
                  onIdle: _scheduleAddress,
                  onLoadError: () => setState(() => _mapFailed = true),
                ),
                const CentrePin(),
                // Search on top, results under it.
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Column(
                    children: [
                      Material(
                        elevation: 3,
                        borderRadius: BorderRadius.circular(28),
                        child: TextField(
                          key: const Key('placeSearch'),
                          controller: _search,
                          focusNode: _searchFocus,
                          textInputAction: TextInputAction.search,
                          onChanged: _onSearchChanged,
                          onSubmitted: (t) {
                            if (t.trim().length >= 2) _runSearch(t.trim());
                          },
                          decoration: InputDecoration(
                            hintText: s.searchPlaceHint,
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searching
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : _search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: s.close,
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () => setState(() {
                                      _search.clear();
                                      _results = null;
                                    }),
                                  ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      if (_results != null)
                        Container(
                          key: const Key('placeResults'),
                          margin: const EdgeInsets.only(top: 6),
                          constraints: const BoxConstraints(maxHeight: 280),
                          child: Material(
                            color: Colors.white,
                            elevation: 3,
                            borderRadius: AppTheme.radius,
                            clipBehavior: Clip.antiAlias,
                            child: _results!.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(s.noPlacesFound, style: const TextStyle(color: AppColors.muted)),
                                  )
                                : ListView(
                                    shrinkWrap: true,
                                    padding: EdgeInsets.zero,
                                    children: [
                                      for (final p in _results!)
                                        ListTile(
                                          leading: const Icon(Icons.place_rounded, color: AppColors.red),
                                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                          subtitle: Text(p.address, maxLines: 2, overflow: TextOverflow.ellipsis),
                                          onTap: () => _pickResult(p),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_results == null && (_mapFailed || _locating))
                  Positioned(
                    top: 74,
                    left: 16,
                    right: 16,
                    child: _Chip(
                      key: Key(_mapFailed ? 'mapFailed' : 'mapLocating'),
                      text: _mapFailed ? s.mapLoadFailed : s.findingLocation,
                      color: _mapFailed ? AppColors.red : AppColors.ink,
                    ),
                  ),
                if (useGoogleMaps)
                  Positioned(
                    right: 12,
                    bottom: 76,
                    child: SegmentedButton<bool>(
                      key: const Key('mapTypeToggle'),
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        backgroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: [
                        ButtonSegment(value: false, label: Text(s.mapView)),
                        ButtonSegment(value: true, label: Text(s.satelliteView)),
                      ],
                      selected: {_satellite},
                      onSelectionChanged: (v) => setState(() => _satellite = v.first),
                    ),
                  ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    key: const Key('mapMyLocation'),
                    heroTag: null,
                    tooltip: s.myLocation,
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.mintDark,
                    onPressed: _locating ? null : () => _goToMe(),
                    child: const Icon(Icons.my_location_rounded),
                  ),
                ),
              ],
            ),
          ),
          // The spot under the pin, and the one button that keeps it.
          Material(
            color: Colors.white,
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.moveMapHint, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.place_rounded, color: AppColors.red, size: 20),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _addressLoading && _address == null ? s.findingAddress : (_address ?? '—'),
                            key: const Key('pickedAddress'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    if (distance != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        inside ? s.youAreInside : s.youAreFromPin(distance),
                        key: const Key('distanceLine'),
                        style: TextStyle(color: inside ? AppColors.mintDark : AppColors.amberDark, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 10),
                    FilledButton(
                      key: const Key('useThisLocation'),
                      onPressed: () => Navigator.of(context).pop(PickedLocation(_center, _address)),
                      child: Text(s.useThisLocation),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
