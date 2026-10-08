/// Defensive JSON helpers. The API is typed, but the app must never crash
/// because a field is missing or arrives as a different numeric type.
library;

typedef Json = Map<String, dynamic>;

int asInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) {
    return int.tryParse(v) ?? double.tryParse(v)?.round() ?? fallback;
  }
  return fallback;
}

int? asIntOrNull(Object? v) => v == null ? null : asInt(v);

double asDouble(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

double? asDoubleOrNull(Object? v) => v == null ? null : asDouble(v);

String asString(Object? v, [String fallback = '']) => v == null ? fallback : v.toString();

String? asStringOrNull(Object? v) => v?.toString();

bool asBool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return fallback;
}

Json asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return <String, dynamic>{};
}

Json? asMapOrNull(Object? v) => v is Map ? asMap(v) : null;

List<T> asList<T>(Object? v, T Function(Json json) parse) {
  if (v is! List) return <T>[];
  return v.whereType<Map>().map((e) => parse(asMap(e))).toList();
}

List<String> asStringList(Object? v) {
  if (v is! List) return const <String>[];
  return v.where((e) => e != null).map((e) => e.toString()).toList();
}

List<int> asIntList(Object? v) {
  if (v is! List) return const <int>[];
  return v.map((e) => asInt(e)).toList();
}

DateTime? asDateTimeOrNull(Object? v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

num asNum(Object? v, [num fallback = 0]) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? fallback;
  return fallback;
}
