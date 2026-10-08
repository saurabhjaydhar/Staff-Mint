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
  const LocationPicker({super.key, required this.value, required this.onChanged, this.radiusM, this.height = 320});

  final LatLng? value;
  final ValueChanged<LatLng> onChanged;
  final double? radiusM;
  final double height;

  /// Centre of India — used until a pin is placed.
  static const fallbackCenter = LatLng(22.9734, 78.6569);

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  final _map = MapController();
  bool _locating = false;

  Future<void> _useCurrent() async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService.current();
      final p = LatLng(pos.latitude, pos.longitude);
      widget.onChanged(p);
      _map.move(p, 17);
    } on LocationException catch (e) {
      if (mounted) {
        showSnack(
          context,
          e.serviceDisabled ? context.s.locationServiceOff : context.s.locationPermissionDenied,
          error: true,
        );
      }
    } catch (_) {
      if (mounted) showSnack(context, context.s.genericError, error: true);
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
            child: FlutterMap(
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
                        child: const Icon(Icons.location_on, color: AppColors.absent, size: 48),
                      ),
                    ],
                  ),
                const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _locating ? null : _useCurrent,
          icon: _locating
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location_rounded),
          label: Text(s.useMyLocation),
        ),
      ],
    );
  }
}
