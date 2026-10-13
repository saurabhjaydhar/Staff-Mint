import { distanceMeters } from '../../lib/geo.js';

export interface TrackPoint {
  at: Date;
  lat: number;
  lng: number;
  accuracyM?: number | null;
}

export interface Stop {
  lat: number;
  lng: number;
  from: Date;
  to: Date;
  minutes: number;
}

/** Points worse than this are left out of distance and stops. */
export const MAX_ACCURACY_M = 100;
/** Faster than this between two points is a GPS jump, not travel (km/h). */
export const MAX_SPEED_KMH = 150;
/** A stop: stayed this long (minutes) within this radius (metres). */
export const STOP_MINUTES = 10;
export const STOP_RADIUS_M = 100;

/** In time order, without bad-accuracy points and GPS jumps (a point that would need an impossible speed). */
export function cleanPoints<T extends TrackPoint>(points: T[]): T[] {
  const sorted = [...points].filter((p) => p.accuracyM == null || p.accuracyM <= MAX_ACCURACY_M).sort((a, b) => a.at.getTime() - b.at.getTime());
  const out: T[] = [];
  for (const p of sorted) {
    const prev = out[out.length - 1];
    if (prev) {
      const hours = (p.at.getTime() - prev.at.getTime()) / 3_600_000;
      const km = distanceMeters(prev, p) / 1000;
      if (hours <= 0 ? km > 0.2 : km / hours > MAX_SPEED_KMH) continue;
    }
    out.push(p);
  }
  return out;
}

/** Distance travelled in metres along clean points (small wobbles inside one place don't add up). */
export function distanceOf(points: TrackPoint[]): number {
  const clean = cleanPoints(points);
  let total = 0;
  let anchor = clean[0];
  for (const p of clean.slice(1)) {
    const d = distanceMeters(anchor, p);
    // Standing still, GPS drifts a few metres each time: only count moves bigger than the noise.
    if (d >= 30) {
      total += d;
      anchor = p;
    }
  }
  return Math.round(total);
}

/** Places where the person stayed at least STOP_MINUTES within STOP_RADIUS_M. */
export function stopsOf(points: TrackPoint[]): Stop[] {
  const clean = cleanPoints(points);
  const stops: Stop[] = [];
  let i = 0;
  while (i < clean.length) {
    let j = i;
    let lat = clean[i].lat;
    let lng = clean[i].lng;
    // Grow the cluster while points stay near its centre.
    while (j + 1 < clean.length && distanceMeters({ lat, lng }, clean[j + 1]) <= STOP_RADIUS_M) {
      j++;
      const n = j - i + 1;
      lat += (clean[j].lat - lat) / n;
      lng += (clean[j].lng - lng) / n;
    }
    const minutes = (clean[j].at.getTime() - clean[i].at.getTime()) / 60_000;
    if (minutes >= STOP_MINUTES) {
      stops.push({ lat: Number(lat.toFixed(6)), lng: Number(lng.toFixed(6)), from: clean[i].at, to: clean[j].at, minutes: Math.round(minutes) });
      i = j + 1;
    } else i++;
  }
  return stops;
}

/** Fewer points for drawing the route: drop points closer than [minGapM] to the last kept one. */
export function simplify<T extends TrackPoint>(points: T[], minGapM = 25): T[] {
  const clean = cleanPoints(points);
  const out: T[] = [];
  for (const p of clean) {
    const last = out[out.length - 1];
    if (!last || distanceMeters(last, p) >= minGapM) out.push(p);
  }
  if (clean.length && out[out.length - 1] !== clean[clean.length - 1]) out.push(clean[clean.length - 1]);
  return out;
}
