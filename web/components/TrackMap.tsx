"use client";

import { useEffect, useRef } from "react";
import "leaflet/dist/leaflet.css";

export interface MapMarker {
  lat: number;
  lng: number;
  label: string;
  color: string;
  title?: string;
  onClick?: () => void;
}

/** Map tiles: a keyed provider in production (NEXT_PUBLIC_MAP_TILE_URL); OpenStreetMap's public tiles in development. */
const TILE_URL = process.env.NEXT_PUBLIC_MAP_TILE_URL || "https://tile.openstreetmap.org/{z}/{x}/{y}.png";

/** Field staff on a map (initials) or one person's route with numbered stops. Fits everything drawn. */
export function TrackMap({ markers = [], route = [], height = 360 }: { markers?: MapMarker[]; route?: [number, number][]; height?: number }) {
  const el = useRef<HTMLDivElement>(null);
  const map = useRef<import("leaflet").Map | null>(null);
  const layer = useRef<import("leaflet").LayerGroup | null>(null);

  useEffect(() => {
    let cancelled = false;
    void import("leaflet").then((L) => {
      if (cancelled || !el.current) return;
      if (!map.current) {
        map.current = L.map(el.current, { zoomControl: true, attributionControl: true }).setView([28.6139, 77.209], 12);
        L.tileLayer(TILE_URL, { maxZoom: 19, attribution: "© OpenStreetMap" }).addTo(map.current);
        layer.current = L.layerGroup().addTo(map.current);
      }
      const g = layer.current!;
      g.clearLayers();
      const pts: [number, number][] = [...route];
      if (route.length > 1) L.polyline(route, { color: "#0f7a52", weight: 5 }).addTo(g);
      for (const m of markers) {
        pts.push([m.lat, m.lng]);
        const icon = L.divIcon({
          className: "",
          iconSize: [34, 34],
          iconAnchor: [17, 17],
          html: `<div style="width:34px;height:34px;border-radius:50%;background:${m.color};color:#fff;font:700 12px system-ui;display:flex;align-items:center;justify-content:center;border:2px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.35)">${m.label.replace(/[<>&]/g, "")}</div>`,
        });
        const mk = L.marker([m.lat, m.lng], { icon, title: m.title ?? m.label }).addTo(g);
        if (m.onClick) mk.on("click", m.onClick);
      }
      if (pts.length > 1) map.current!.fitBounds(L.latLngBounds(pts), { padding: [40, 40], maxZoom: 16 });
      else if (pts.length === 1) map.current!.setView(pts[0], 15);
    });
    return () => {
      cancelled = true;
    };
  }, [markers, route]);

  useEffect(
    () => () => {
      map.current?.remove();
      map.current = null;
    },
    [],
  );

  return <div ref={el} style={{ height }} className="z-0 w-full overflow-hidden rounded-xl bg-slate-100 ring-1 ring-slate-200" data-testid="track-map" />;
}
