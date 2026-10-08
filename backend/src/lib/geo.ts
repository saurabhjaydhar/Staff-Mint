export interface LatLng {
  lat: number;
  lng: number;
}

/** Great-circle distance in metres (haversine). */
export function distanceMeters(a: LatLng, b: LatLng): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(h)));
}

export const toGeoPoint = (p: LatLng) => ({ type: 'Point' as const, coordinates: [p.lng, p.lat] as [number, number] });
export const fromGeoPoint = (g?: { coordinates?: number[] } | null): LatLng | null =>
  g?.coordinates?.length === 2 ? { lat: g.coordinates[1], lng: g.coordinates[0] } : null;
