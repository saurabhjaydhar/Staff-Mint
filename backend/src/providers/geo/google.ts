import type { GeoPlace, GeoProvider } from '../types.js';

/** Google Geocoding (pin → address) and Places Text Search (typed name → places), India-first. */
export class GoogleGeoProvider implements GeoProvider {
  readonly name = 'google';
  constructor(private apiKey: string) {}

  async reverseGeocode(lat: number, lng: number, language: 'en' | 'hi' = 'en') {
    const res = await fetch(
      `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&language=${language}&key=${this.apiKey}`,
    );
    const json: any = await res.json().catch(() => ({}));
    return { address: json?.results?.[0]?.formatted_address ?? null };
  }

  async search(query: string, opts: { near?: { lat: number; lng: number }; language?: 'en' | 'hi' } = {}): Promise<GeoPlace[]> {
    const res = await fetch('https://places.googleapis.com/v1/places:searchText', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': this.apiKey,
        'X-Goog-FieldMask': 'places.displayName,places.formattedAddress,places.location',
      },
      body: JSON.stringify({
        textQuery: query,
        regionCode: 'IN',
        languageCode: opts.language ?? 'en',
        pageSize: 6,
        ...(opts.near ? { locationBias: { circle: { center: { latitude: opts.near.lat, longitude: opts.near.lng }, radius: 20000 } } } : {}),
      }),
    });
    const json: any = await res.json().catch(() => ({}));
    return (json?.places ?? [])
      .filter((p: any) => p?.location)
      .map((p: any) => ({
        name: p.displayName?.text ?? query,
        address: p.formattedAddress ?? '',
        lat: p.location.latitude,
        lng: p.location.longitude,
      }));
  }
}
