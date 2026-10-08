import type { GeoProvider } from '../types.js';

export class MockGeoProvider implements GeoProvider {
  readonly name = 'mock';
  async reverseGeocode(lat: number, lng: number) {
    return { address: `${lat.toFixed(5)}, ${lng.toFixed(5)}` };
  }
}
