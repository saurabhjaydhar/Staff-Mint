import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import '../config/env.dart';
import '../theme/app_theme.dart';
import 'shop_map.dart' show useGoogleMaps;

/// A point drawn on the map: initials or a number in a coloured circle.
class TrackMarker {
  const TrackMarker({required this.point, required this.label, required this.color, this.title, this.onTap});
  final LatLng point;
  final String label;
  final Color color;

  /// Shown when the pin is tapped on Google Maps.
  final String? title;
  final VoidCallback? onTap;
}

/// Field staff on a map (live) or one person's route with stops. Google Maps on phones with a key, the
/// OpenStreetMap-style map elsewhere. The camera fits everything drawn.
class TrackMap extends StatelessWidget {
  const TrackMap({super.key, this.markers = const [], this.route = const [], this.height = 280});
  final List<TrackMarker> markers;
  final List<LatLng> route;
  final double height;

  /// Tests have no map pictures: draw the layers without tiles.
  static bool showTiles = true;

  List<LatLng> get _all => [...route, ...markers.map((m) => m.point)];

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final center = all.isEmpty
        ? const LatLng(28.6139, 77.2090)
        : LatLng(
            all.map((p) => p.latitude).reduce((a, b) => a + b) / all.length,
            all.map((p) => p.longitude).reduce((a, b) => a + b) / all.length,
          );
    return SizedBox(
      height: height,
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: useGoogleMaps ? _google(center) : _osm(center)),
    );
  }

  Widget _google(LatLng center) {
    final all = _all;
    final hue = {
      AppColors.mint: gm.BitmapDescriptor.hueGreen,
      AppColors.amber: gm.BitmapDescriptor.hueOrange,
      AppColors.red: gm.BitmapDescriptor.hueRed,
    };
    return gm.GoogleMap(
      initialCameraPosition: gm.CameraPosition(target: gm.LatLng(center.latitude, center.longitude), zoom: 13),
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      myLocationButtonEnabled: false,
      markers: {
        for (final (i, m) in markers.indexed)
          gm.Marker(
            markerId: gm.MarkerId('m$i'),
            position: gm.LatLng(m.point.latitude, m.point.longitude),
            icon: gm.BitmapDescriptor.defaultMarkerWithHue(hue[m.color] ?? gm.BitmapDescriptor.hueAzure),
            infoWindow: gm.InfoWindow(title: m.title ?? m.label, onTap: m.onTap),
          ),
      },
      polylines: {
        if (route.length > 1)
          gm.Polyline(
            polylineId: const gm.PolylineId('route'),
            points: [for (final p in route) gm.LatLng(p.latitude, p.longitude)],
            color: AppColors.mintDark,
            width: 5,
          ),
      },
      onMapCreated: (c) {
        if (all.length < 2) return;
        final b = _bounds(all);
        Future.delayed(const Duration(milliseconds: 300), () {
          c.animateCamera(
            gm.CameraUpdate.newLatLngBounds(
              gm.LatLngBounds(southwest: gm.LatLng(b.south, b.west), northeast: gm.LatLng(b.north, b.east)),
              48,
            ),
          );
        });
      },
    );
  }

  Widget _osm(LatLng center) {
    final all = _all;
    final fit = all.length > 1
        ? fm.CameraFit.bounds(bounds: _bounds(all), padding: const EdgeInsets.all(40), maxZoom: 16)
        : null;
    return fm.FlutterMap(
      options: fm.MapOptions(initialCenter: center, initialZoom: 14, initialCameraFit: fit),
      children: [
        if (showTiles) fm.TileLayer(urlTemplate: Env.mapTileUrl, userAgentPackageName: Env.userAgentPackageName),
        if (route.length > 1)
          fm.PolylineLayer(
            polylines: [fm.Polyline(points: route, color: AppColors.mintDark, strokeWidth: 5)],
          ),
        fm.MarkerLayer(
          markers: [
            for (final m in markers)
              fm.Marker(
                point: m.point,
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: m.onTap,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: m.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 4, offset: Offset(0, 1))],
                    ),
                    child: Text(
                      m.label,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: Text('© OpenStreetMap', style: TextStyle(fontSize: 10, color: AppColors.muted)),
          ),
        ),
      ],
    );
  }

  static fm.LatLngBounds _bounds(List<LatLng> pts) => fm.LatLngBounds.fromPoints(pts);
}
