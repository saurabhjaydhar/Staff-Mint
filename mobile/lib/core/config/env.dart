/// Compile-time configuration supplied through `--dart-define-from-file`.
///
/// Example:
///   flutter run --dart-define-from-file=config/production.json
class Env {
  Env._();

  /// Base URL of the StaffMint API including the `/api/v1` prefix.
  /// No default: always supplied by a file in `config/` (local.json, production.json).
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// OpenStreetMap tile server used by the location pickers.
  static const String mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// Use Google Maps for the shop location picker (Android/iOS builds that carry a Maps key:
  /// `--dart-define=GOOGLE_MAPS=true` plus `MAPS_API_KEY` for the native build). Off → the
  /// OpenStreetMap-style fallback (web, tests, local dev).
  static const bool googleMaps = bool.fromEnvironment('GOOGLE_MAPS');

  /// Package name sent to the tile server as the user agent (OSM policy).
  static const String userAgentPackageName = 'com.staffmint.app';
}
