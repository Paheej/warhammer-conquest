'use client';

// =====================================================================
// app/map/OrbitalMap.tsx
// Client map. Renders planets as positioned circles over a starfield.
// Uses planet.image_url if provided. Responsive via aspect-ratio wrapper.
// =====================================================================

import { useMemo, useState } from 'react';
import Link from 'next/link';
import type { MapFaction, MapPlanet, MapPoint } from './page';

interface Props {
  planets:  MapPlanet[];
  points:   MapPoint[];
  factions: MapFaction[];
}

export default function OrbitalMap({ planets, points, factions }: Props) {
  const [hovered, setHovered] = useState<string | null>(null);

  const factionById = useMemo(() => {
    const m = new Map<string, MapFaction>();
    for (const f of factions) m.set(f.id, f);
    return m;
  }, [factions]);

  const pointsByPlanet = useMemo(() => {
    const m = new Map<string, MapPoint[]>();
    for (const p of points) {
      const arr = m.get(p.planet_id) ?? [];
      arr.push(p);
      m.set(p.planet_id, arr);
    }
    for (const [, arr] of m) arr.sort((a, b) => b.points - a.points);
    return m;
  }, [points]);

  const hoveredPlanet = hovered ? planets.find((p) => p.id === hovered) : null;
  const hoveredPoints = hovered ? pointsByPlanet.get(hovered) ?? [] : [];

  return (
    <div className="flex flex-col gap-4 lg:flex-row">
      {/* Map canvas */}
      <div className="relative w-full overflow-hidden rounded border border-brass-700/40 bg-[#0b0a14] lg:flex-[2]">
        {/* Starfield background */}
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 opacity-60"
          style={{
            backgroundImage: `
              radial-gradient(1px 1px at 20% 30%, #eadca5 50%, transparent 51%),
              radial-gradient(1px 1px at 70% 60%, #eadca5 50%, transparent 51%),
              radial-gradient(1px 1px at 40% 80%, #b8933f 50%, transparent 51%),
              radial-gradient(1.5px 1.5px at 85% 25%, #ffffff 50%, transparent 51%),
              radial-gradient(1px 1px at 10% 70%, #eadca5 50%, transparent 51%),
              radial-gradient(1px 1px at 55% 15%, #ffffff 50%, transparent 51%)
            `,
          }}
        />
        {/* Keep a fixed aspect ratio so planet coordinates stay stable */}
        <div className="relative" style={{ aspectRatio: '16 / 10' }}>
          {planets.map((p) => {
            const x = (p.position_x ?? 0.5) * 100;
            const y = (p.position_y ?? 0.5) * 100;
            const ptsRows = pointsByPlanet.get(p.id) ?? [];
            const total = ptsRows.reduce((a, b) => a + b.points, 0);
            const controllingColor = p.controlling_faction_id
              ? factionById.get(p.controlling_faction_id)?.color ?? null
              : null;
            const isHover = hovered === p.id;

            return (
              <button
                key={p.id}
                type="button"
                onMouseEnter={() => setHovered(p.id)}
                onMouseLeave={() => setHovered(null)}
                onFocus={() => setHovered(p.id)}
                onBlur={() => setHovered(null)}
                className="group absolute -translate-x-1/2 -translate-y-1/2 transform"
                style={{ left: `${x}%`, top: `${y}%` }}
                aria-label={p.name}
              >
                {/* Control ring */}
                <div
                  className={`absolute inset-0 rounded-full transition-transform ${isHover ? 'scale-125' : 'scale-110'}`}
                  style={{
                    boxShadow: controllingColor
                      ? `0 0 0 2px ${controllingColor}, 0 0 24px ${controllingColor}66`
                      : '0 0 0 1px rgba(234,220,165,0.3)',
                  }}
                />
                {/* Planet body */}
                <div
                  className={`relative h-10 w-10 overflow-hidden rounded-full border border-brass-700/60 transition-transform sm:h-12 sm:w-12 ${
                    isHover ? 'scale-110' : ''
                  }`}
                  style={{
                    backgroundColor: controllingColor ?? '#2b2840',
                  }}
                >
                  {p.image_url ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={p.image_url}
                      alt=""
                      className="h-full w-full object-cover"
                      onError={(e) => { (e.currentTarget as HTMLImageElement).style.display = 'none'; }}
                    />
                  ) : null}
                </div>
                {/* Label */}
                <div className="absolute left-1/2 top-full mt-1 -translate-x-1/2 whitespace-nowrap font-cinzel text-[10px] text-brass-200 sm:text-xs">
                  {p.name}
                </div>
                {total > 0 && (
                  <div className="absolute bottom-full left-1/2 mb-1 -translate-x-1/2 whitespace-nowrap rounded bg-parchment-950/80 px-1 text-[9px] text-parchment-200 sm:text-[10px]">
                    {total}/{p.claim_threshold}
                  </div>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* Side panel */}
      <aside className="w-full rounded border border-brass-700/40 bg-parchment-900/50 p-4 lg:flex-1">
        {hoveredPlanet ? (
          <div>
            <div className="flex items-center gap-3">
              <div className="h-12 w-12 overflow-hidden rounded-full border border-brass-700/50 bg-parchment-800">
                {hoveredPlanet.image_url ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={hoveredPlanet.image_url} alt="" className="h-full w-full object-cover" />
                ) : null}
              </div>
              <div>
                <h2 className="font-cinzel text-xl text-brass-100">{hoveredPlanet.name}</h2>
                <p className="text-xs text-parchment-400">
                  Threshold {hoveredPlanet.claim_threshold}
                  {hoveredPlanet.controlling_faction_id && (() => {
                    const f = factionById.get(hoveredPlanet.controlling_faction_id!);
                    return f ? <> · controlled by <span style={{ color: f.color ?? undefined }}>{f.name}</span></> : null;
                  })()}
                </p>
              </div>
            </div>

            <h3 className="mt-4 font-cinzel text-sm uppercase tracking-wider text-brass-300">
              Contesting factions
            </h3>
            {hoveredPoints.length === 0 ? (
              <p className="mt-1 text-sm text-parchment-400">No battles fought here yet.</p>
            ) : (
              <ul className="mt-2 flex flex-col gap-1.5">
                {hoveredPoints.map((row) => {
                  const f = factionById.get(row.faction_id);
                  if (!f) return null;
                  const pct = Math.min(100, (row.points / hoveredPlanet.claim_threshold) * 100);
                  return (
                    <li key={row.faction_id} className="text-sm">
                      <div className="flex items-center justify-between text-parchment-100">
                        <span className="inline-flex items-center gap-2">
                          <span
                            className="inline-block h-2.5 w-2.5 rounded-full"
                            style={{ backgroundColor: f.color ?? '#7a5b20' }}
                          />
                          {f.name}
                        </span>
                        <span className="text-parchment-300">
                          {row.points}/{hoveredPlanet.claim_threshold}
                        </span>
                      </div>
                      <div className="mt-0.5 h-1.5 overflow-hidden rounded-full bg-parchment-950">
                        <div
                          className="h-full rounded-full"
                          style={{ width: `${pct}%`, backgroundColor: f.color ?? '#7a5b20' }}
                        />
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}

            <Link
              href={`/leaderboard?planet=${hoveredPlanet.id}`}
              className="mt-4 inline-block text-xs text-brass-300 hover:text-brass-100"
            >
              View leaderboard filtered to this world →
            </Link>
          </div>
        ) : (
          <div className="text-sm text-parchment-400">
            Hover or focus a world to see who contests it.
          </div>
        )}
      </aside>
    </div>
  );
}
