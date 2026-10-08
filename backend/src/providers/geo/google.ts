import type { GeoProvider } from '../types.js';

export class GoogleGeoProvider implements GeoProvider {
  readonly name = 'google';
  constructor(private apiKey: string) {}
  async reverseGeocode(lat: number, lng: number) {
    const res = await fetch(`https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${this.apiKey}`);
    const json: any = await res.json().catch(() => ({}));
    return { address: json?.results?.[0]?.formatted_address ?? null };
  }
}
