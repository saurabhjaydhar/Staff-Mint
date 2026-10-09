import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/env.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../utils/location.dart';
import 'common.dart';

/// OpenStreetMap pin picker with "use my current location" and an optional
/// geofence radius circle. No API key needed.
class LocationPicker extends StatefulWidget {
  const LocationPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.radiusM,
    this.height = 320,
    this.autoLocate = false,
  });

  final LatLng? value;
  final ValueChanged<LatLng> onChanged;
  final double? radiusM;
  final double height;

  /// Try "use my current location" as soon as the picker appears (when no
  /// pin is set yet). Failures stay quiet; tapping the map always works.
  final bool autoLocate;

  /// Centre of India — used until a pin is placed.
  static const fallbackCenter = LatLng(22.9734, 78.6569);

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  final _map = MapController();
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoLocate && widget.value == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useCurrent(quiet: true));
    }
  }

  Future<void> _useCurrent({bool quiet = false}) async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService.current();
      final p = LatLng(pos.latitude, pos.longitude);
      widget.onChanged(p);
      _map.move(p, 17);
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

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final pin = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: pin ?? LocationPicker.fallbackCenter,
                    initialZoom: pin == null ? 4.5 : 17,
                    onTap: (_, latLng) => widget.onChanged(latLng),
                  ),
                  children: [
                    TileLayer(urlTemplate: Env.mapTileUrl, userAgentPackageName: Env.userAgentPackageName),
                    if (pin != null && widget.radiusM != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: pin,
                            radius: widget.radiusM!,
                            useRadiusInMeter: true,
                            color: AppColors.mint.withValues(alpha: 0.18),
                            borderColor: AppColors.mint,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    if (pin != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: pin,
                            width: 48,
                            height: 48,
                            alignment: Alignment.topCenter,
                            child: const Icon(Icons.location_on, color: AppColors.red, size: 48),
                          ),
                        ],
                      ),
                    const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
                  ],
                ),
                if (_locating)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            Text(s.findingLocation, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _locating ? null : () => _useCurrent(),
          icon: _locating
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location_rounded),
          label: Text(s.useMyLocation),
        ),
      ],
    );
  }
}
