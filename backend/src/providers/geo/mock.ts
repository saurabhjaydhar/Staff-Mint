import type { GeoPlace, GeoProvider } from '../types.js';

/** Offline stand-in: a few places around Connaught Place, New Delhi, so search works without a key. */
const PLACES: GeoPlace[] = [
  { name: 'Sharma Medical Store', address: 'Block A, Connaught Place, New Delhi 110001', lat: 28.6315, lng: 77.2167 },
  { name: 'Connaught Place', address: 'Connaught Place, New Delhi 110001', lat: 28.6304, lng: 77.2177 },
  { name: 'Karol Bagh Market', address: 'Ajmal Khan Road, Karol Bagh, New Delhi 110005', lat: 28.6514, lng: 77.1907 },
  { name: 'Lajpat Nagar Central Market', address: 'Lajpat Nagar II, New Delhi 110024', lat: 28.5677, lng: 77.2433 },
  { name: 'Chandni Chowk', address: 'Chandni Chowk, Old Delhi 110006', lat: 28.6506, lng: 77.2303 },
  { name: 'Sector 18 Market', address: 'Sector 18, Noida, Uttar Pradesh 201301', lat: 28.5708, lng: 77.3261 },
];

export class MockGeoProvider implements GeoProvider {
  readonly name = 'mock';

  async reverseGeocode(lat: number, lng: number) {
    const near = PLACES.map((p) => ({ p, d: Math.hypot(p.lat - lat, p.lng - lng) })).sort((a, b) => a.d - b.d)[0];
    // Within ~1 km of a known place: use its area; otherwise the coordinates.
    return { address: near && near.d < 0.01 ? near.p.address : `${lat.toFixed(5)}, ${lng.toFixed(5)}` };
  }

  async search(query: string) {
    const q = query.trim().toLowerCase();
    if (!q) return [];
    return PLACES.filter((p) => `${p.name} ${p.address}`.toLowerCase().includes(q)).slice(0, 6);
  }
}
