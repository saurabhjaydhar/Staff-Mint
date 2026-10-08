/// Compile-time configuration supplied through `--dart-define`.
///
/// Example:
///   flutter run --dart-define=API_BASE_URL=https://api.staffmint.app/api/v1
class Env {
  Env._();

  /// Base URL of the StaffMint API including the `/api/v1` prefix.
  /// Defaults to the Android emulator's alias for the host machine.
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:4000/api/v1');

  /// OpenStreetMap tile server used by the location pickers.
  static const String mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// Package name sent to the tile server as the user agent (OSM policy).
  static const String userAgentPackageName = 'com.staffmint.app';
}
