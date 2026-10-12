import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import '../config/env.dart';
import '../theme/app_theme.dart';

/// Google Maps on Android/iOS builds with a key; the OpenStreetMap-style map elsewhere.
bool get useGoogleMaps =>
    Env.googleMaps &&
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Lets a parent move the camera (search result, "my location").
class ShopMapController {
  void Function(LatLng target, double zoom)? _move;

  void moveTo(LatLng target, {double zoom = 17}) => _move?.call(target, zoom);
}

/// The map with a circle of [radiusM] around the camera centre. The pin itself is drawn by the
/// parent on top, fixed in the middle, so the owner moves the map under it (like Google Maps).
class ShopMap extends StatefulWidget {
  const ShopMap({
    super.key,
    required this.initialCenter,
    this.initialZoom = 17,
    this.radiusM,
    this.interactive = true,
    this.satellite = false,
    this.showMyLocation = false,
    this.controller,
    this.onMove,
    this.onIdle,
    this.onLoadError,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final double? radiusM;
  final bool interactive;
  final bool satellite;

  /// Blue "you are here" dot (Google only; needs location permission already granted).
  final bool showMyLocation;
  final ShopMapController? controller;
  final ValueChanged<LatLng>? onMove;
  final ValueChanged<LatLng>? onIdle;

  /// Map pictures failed to load (no internet, blocked server).
  final VoidCallback? onLoadError;

  @override
  State<ShopMap> createState() => _ShopMapState();
}

class _ShopMapState extends State<ShopMap> {
  late LatLng _center = widget.initialCenter;
  final _osm = fm.MapController();
  gm.GoogleMapController? _google;
  bool _errorReported = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._move = (target, zoom) {
      if (useGoogleMaps) {
        _google?.animateCamera(gm.CameraUpdate.newLatLngZoom(gm.LatLng(target.latitude, target.longitude), zoom));
      } else {
        _osm.move(target, zoom);
        _moved(target);
        widget.onIdle?.call(target);
      }
    };
  }

  void _moved(LatLng c) {
    setState(() => _center = c);
    widget.onMove?.call(c);
  }

  @override
  Widget build(BuildContext context) => useGoogleMaps ? _googleMap() : _osmMap();

  Widget _googleMap() {
    final c = gm.LatLng(_center.latitude, _center.longitude);
    final interactive = widget.interactive;
    return gm.GoogleMap(
      initialCameraPosition: gm.CameraPosition(
        target: gm.LatLng(widget.initialCenter.latitude, widget.initialCenter.longitude),
        zoom: widget.initialZoom,
      ),
      mapType: widget.satellite ? gm.MapType.hybrid : gm.MapType.normal,
      myLocationEnabled: widget.showMyLocation,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      liteModeEnabled: !interactive && defaultTargetPlatform == TargetPlatform.android,
      scrollGesturesEnabled: interactive,
      zoomGesturesEnabled: interactive,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      circles: {
        if (widget.radiusM != null)
          gm.Circle(
            circleId: const gm.CircleId('area'),
            center: c,
            radius: widget.radiusM!,
            fillColor: AppColors.mint.withValues(alpha: 0.18),
            strokeColor: AppColors.mint,
            strokeWidth: 2,
          ),
      },
      onMapCreated: (ctrl) => _google = ctrl,
      onCameraMove: (pos) => _moved(LatLng(pos.target.latitude, pos.target.longitude)),
      onCameraIdle: () => widget.onIdle?.call(_center),
    );
  }

  Widget _osmMap() => fm.FlutterMap(
    mapController: _osm,
    options: fm.MapOptions(
      initialCenter: widget.initialCenter,
      initialZoom: widget.initialZoom,
      interactionOptions: fm.InteractionOptions(
        flags: widget.interactive
            ? fm.InteractiveFlag.drag |
                  fm.InteractiveFlag.pinchZoom |
                  fm.InteractiveFlag.doubleTapZoom |
                  fm.InteractiveFlag.scrollWheelZoom
            : fm.InteractiveFlag.none,
      ),
      onPositionChanged: (camera, hasGesture) {
        if (hasGesture) _moved(camera.center);
      },
      onMapEvent: (e) {
        if (e is fm.MapEventMoveEnd || e is fm.MapEventFlingAnimationEnd || e is fm.MapEventDoubleTapZoomEnd) {
          widget.onIdle?.call(_center);
        }
      },
    ),
    children: [
      fm.TileLayer(
        urlTemplate: Env.mapTileUrl,
        userAgentPackageName: Env.userAgentPackageName,
        errorTileCallback: (tile, error, stack) {
          if (_errorReported) return;
          _errorReported = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLoadError?.call());
        },
      ),
      if (widget.radiusM != null)
        fm.CircleLayer(
          circles: [
            fm.CircleMarker(
              point: _center,
              radius: widget.radiusM!,
              useRadiusInMeter: true,
              color: AppColors.mint.withValues(alpha: 0.18),
              borderColor: AppColors.mint,
              borderStrokeWidth: 2,
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

/// The red pin, drawn so its tip sits exactly on the map centre.
class CentrePin extends StatelessWidget {
  const CentrePin({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Transform.translate(
        offset: Offset(0, -size / 2),
        child: Icon(
          Icons.location_on,
          color: AppColors.red,
          size: size,
          shadows: const [Shadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
      ),
    ),
  );
}
