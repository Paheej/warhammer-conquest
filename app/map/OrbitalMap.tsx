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

// Hand-placed stars in the 160x100 viewBox shared by the background SVG.
// Distribution skirts the rift band so the rift reads cleanly.
const STARS: { x: number; y: number; r: number; c: string; o: number }[] = [
  // Upper field
  { x: 8,   y: 10, r: 0.18, c: '#eadca5', o: 0.7  },
  { x: 24,  y: 14, r: 0.30, c: '#ffffff', o: 0.85 },
  { x: 42,  y: 6,  r: 0.20, c: '#eadca5', o: 0.65 },
  { x: 58,  y: 20, r: 0.25, c: '#ffffff', o: 0.8  },
  { x: 72,  y: 8,  r: 0.18, c: '#b8933f', o: 0.6  },
  { x: 88,  y: 18, r: 0.30, c: '#ffffff', o: 0.9  },
  { x: 104, y: 12, r: 0.22, c: '#eadca5', o: 0.7  },
  { x: 122, y: 22, r: 0.18, c: '#ffffff', o: 0.65 },
  { x: 138, y: 9,  r: 0.28, c: '#eadca5', o: 0.85 },
  { x: 152, y: 20, r: 0.20, c: '#b8933f', o: 0.6  },
  { x: 16,  y: 28, r: 0.22, c: '#ffffff', o: 0.7  },
  { x: 96,  y: 30, r: 0.18, c: '#eadca5', o: 0.6  },
  // Lower field
  { x: 12,  y: 78, r: 0.25, c: '#eadca5', o: 0.8  },
  { x: 30,  y: 88, r: 0.18, c: '#ffffff', o: 0.65 },
  { x: 48,  y: 76, r: 0.30, c: '#ffffff', o: 0.85 },
  { x: 64,  y: 92, r: 0.20, c: '#b8933f', o: 0.6  },
  { x: 78,  y: 80, r: 0.28, c: '#eadca5', o: 0.8  },
  { x: 94,  y: 90, r: 0.18, c: '#ffffff', o: 0.65 },
  { x: 110, y: 78, r: 0.22, c: '#eadca5', o: 0.7  },
  { x: 126, y: 86, r: 0.30, c: '#ffffff', o: 0.85 },
  { x: 144, y: 78, r: 0.20, c: '#eadca5', o: 0.65 },
  { x: 22,  y: 72, r: 0.18, c: '#ffffff', o: 0.55 },
  { x: 60,  y: 70, r: 0.22, c: '#eadca5', o: 0.65 },
  { x: 116, y: 72, r: 0.18, c: '#b8933f', o: 0.55 },
  { x: 154, y: 92, r: 0.25, c: '#ffffff', o: 0.75 },
];

export default function OrbitalMap({ planets, points, factions }: Props) {
  // Two-state model: a hover overrides whatever is pinned, so moving the
  // cursor to a new world swaps the panel immediately. A click pins the
  // current planet so it survives mouse-leave; hovering a *different*
  // world clears the pin (per spec). Clicking blank canvas also clears.
  const [hovered, setHovered] = useState<string | null>(null);
  const [pinned, setPinned]   = useState<string | null>(null);

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

  const activeId = hovered ?? pinned;
  const hoveredPlanet = activeId ? planets.find((p) => p.id === activeId) : null;
  const hoveredPoints = activeId ? pointsByPlanet.get(activeId) ?? [] : [];

  function enterPlanet(id: string) {
    setHovered(id);
    if (pinned && pinned !== id) setPinned(null);
  }
  function leavePlanet() {
    setHovered(null);
  }
  function clickPlanet(id: string, e: React.MouseEvent) {
    e.stopPropagation();
    setPinned((prev) => (prev === id ? null : id));
  }

  return (
    <div className="flex flex-col gap-4 lg:flex-row">
      {/* Map canvas. Clicks on the canvas (outside any planet button)
          clear the pinned selection — planet onClick stops propagation. */}
      <div
        onClick={() => setPinned(null)}
        className="relative w-full overflow-hidden rounded border border-brass/30 bg-[#0b0a14] lg:flex-[2]"
      >
        {/* Starfield + Great Rift background */}
        <svg
          aria-hidden
          viewBox="0 0 160 100"
          preserveAspectRatio="none"
          className="pointer-events-none absolute inset-0 h-full w-full"
        >
          <defs>
            <radialGradient id="riftHalo" cx="50%" cy="50%" r="50%">
              <stop offset="0%"   stopColor="#ff5c8a" stopOpacity="0.28" />
              <stop offset="35%"  stopColor="#a14dff" stopOpacity="0.16" />
              <stop offset="100%" stopColor="#5a2bb0" stopOpacity="0"    />
            </radialGradient>
            <linearGradient id="riftCore" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0%"   stopColor="#ff79c6" stopOpacity="0"    />
              <stop offset="20%"  stopColor="#ff79c6" stopOpacity="0.28" />
              <stop offset="50%"  stopColor="#bd5cff" stopOpacity="0.35" />
              <stop offset="80%"  stopColor="#ff4d6d" stopOpacity="0.28" />
              <stop offset="100%" stopColor="#ff4d6d" stopOpacity="0"    />
            </linearGradient>
            <filter id="riftBlur" x="-20%" y="-50%" width="140%" height="200%">
              <feGaussianBlur stdDeviation="1.6" />
            </filter>
          </defs>

          {/* Great Rift — rotated slightly off horizontal */}
          <g transform="rotate(-10 80 50)">
            {/* Nebular halo enveloping the rift */}
            <ellipse cx="80" cy="52" rx="90" ry="20" fill="url(#riftHalo)" />
            {/* Jagged warp-tear core */}
            <g filter="url(#riftBlur)" opacity="0.85">
              <path
                d="M -10 53 L 12 48 L 22 54 L 34 47 L 46 53 L 58 46 L 72 52 L 86 45 L 100 51 L 114 44 L 128 50 L 142 43 L 156 49 L 170 51 L 170 57 L 146 61 L 132 55 L 118 61 L 104 55 L 90 61 L 76 55 L 62 61 L 48 55 L 34 61 L 22 56 L 10 61 L -10 59 Z"
                fill="url(#riftCore)"
              />
            </g>
          </g>

          {/* Starfield */}
          <g>
            {STARS.map((s, i) => (
              <circle key={i} cx={s.x} cy={s.y} r={s.r} fill={s.c} opacity={s.o} />
            ))}
          </g>
        </svg>
        {/* Keep a fixed aspect ratio so planet coordinates stay stable */}
        <div className="relative" style={{ aspectRatio: '16 / 10' }}>
          {planets.map((p) => {
            const x = (p.position_x ?? 0.5) * 100;
            const y = (p.position_y ?? 0.5) * 100;
            const ptsRows = pointsByPlanet.get(p.id) ?? [];
            const controllingColor = p.controlling_faction_id
              ? factionById.get(p.controlling_faction_id)?.color ?? null
              : null;
            const isActive = activeId === p.id;
            const isPinned = pinned === p.id;

            // Halo — leader's progress vs threshold, drawn as a single arc.
            const threshold = Math.max(1, p.claim_threshold);
            const leaderRow = ptsRows[0];
            const leaderFrac = leaderRow ? Math.min(leaderRow.points / threshold, 1) : 0;
            const leaderColor = leaderRow ? factionById.get(leaderRow.faction_id)?.color ?? '#7a5b20' : null;
            const R_OUTER = 46;
            const C_OUTER = 2 * Math.PI * R_OUTER;

            return (
              <button
                key={p.id}
                type="button"
                onMouseEnter={() => enterPlanet(p.id)}
                onMouseLeave={leavePlanet}
                onFocus={() => enterPlanet(p.id)}
                onBlur={leavePlanet}
                onClick={(e) => clickPlanet(p.id, e)}
                className="group absolute -translate-x-1/2 -translate-y-1/2 transform"
                style={{ left: `${x}%`, top: `${y}%` }}
                aria-label={p.name}
                aria-pressed={isPinned}
              >
                {/* Halo wrapper — only slightly larger than the planet body so
                    the ring hugs the planet. Body centered inside. */}
                <div
                  className={`relative h-12 w-12 transition-transform sm:h-14 sm:w-14 ${
                    isActive ? 'scale-110' : ''
                  }`}
                >
                  {/* Outer glow for controlled planets */}
                  {controllingColor && (
                    <div
                      aria-hidden
                      className="absolute inset-1 rounded-full"
                      style={{ boxShadow: `0 0 24px ${controllingColor}66` }}
                    />
                  )}
                  {/* Leader-progress halo + threshold tick at 12 o'clock */}
                  <svg
                    aria-hidden
                    viewBox="0 0 100 100"
                    className="pointer-events-none absolute inset-0 h-full w-full"
                    style={{ overflow: 'visible' }}
                  >
                    <circle cx="50" cy="50" r={R_OUTER} fill="none" stroke="rgba(234,220,165,0.2)" strokeWidth="4" />
                    {leaderRow && leaderColor && leaderFrac > 0 && (
                      <circle
                        cx="50" cy="50" r={R_OUTER}
                        fill="none"
                        stroke={leaderColor}
                        strokeWidth="4"
                        strokeDasharray={`${leaderFrac * C_OUTER} ${C_OUTER}`}
                        strokeLinecap="butt"
                        transform="rotate(-90 50 50)"
                      />
                    )}
                    {/* Threshold tick at 12 o'clock — the finish line */}
                    <line
                      x1="50" y1={50 - R_OUTER - 5}
                      x2="50" y2={50 - R_OUTER + 5}
                      stroke="#eadca5" strokeOpacity="0.95" strokeWidth="2"
                    />
                  </svg>
                  {/* Planet body, centered inside the wrapper */}
                  <div
                    className="absolute left-1/2 top-1/2 h-10 w-10 -translate-x-1/2 -translate-y-1/2 overflow-hidden rounded-full border border-brass/60 sm:h-12 sm:w-12"
                    style={{ backgroundColor: controllingColor ?? '#2b2840' }}
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
                </div>
                {/* Label */}
                <div className="absolute left-1/2 top-full -translate-x-1/2 whitespace-nowrap font-display text-[10px] text-brass-bright sm:text-xs">
                  {p.name}
                </div>
              </button>
            );
          })}
        </div>
      </div>

      {/* Side panel */}
      <aside className="card w-full p-4 lg:flex-1">
        {hoveredPlanet ? (
          <div>
            <div className="flex items-center gap-3">
              <div className="h-12 w-12 overflow-hidden rounded-full border border-brass/50 bg-ink-3">
                {hoveredPlanet.image_url ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={hoveredPlanet.image_url} alt="" className="h-full w-full object-cover" />
                ) : null}
              </div>
              <div>
                <h2 className="font-display text-xl text-parchment">{hoveredPlanet.name}</h2>
                <p className="text-xs text-parchment-dark">
                  Threshold {hoveredPlanet.claim_threshold}
                  {hoveredPlanet.controlling_faction_id && (() => {
                    const f = factionById.get(hoveredPlanet.controlling_faction_id!);
                    return f ? <> · controlled by <span style={{ color: f.color ?? undefined }}>{f.name}</span></> : null;
                  })()}
                </p>
              </div>
            </div>

            {hoveredPlanet.description && (
              <p className="mt-3 whitespace-pre-line font-body text-sm italic leading-relaxed text-parchment-dim">
                {hoveredPlanet.description}
              </p>
            )}

            <h3 className="mt-4 font-display text-sm uppercase tracking-wider text-brass">
              Contesting factions
            </h3>
            {hoveredPoints.length === 0 ? (
              <p className="mt-1 text-sm text-parchment-dark">No battles fought here yet.</p>
            ) : (
              <ul className="mt-2 flex flex-col gap-1.5">
                {hoveredPoints.map((row) => {
                  const f = factionById.get(row.faction_id);
                  if (!f) return null;
                  const pct = Math.min(100, (row.points / hoveredPlanet.claim_threshold) * 100);
                  return (
                    <li key={row.faction_id} className="text-sm">
                      <div className="flex items-center justify-between text-parchment">
                        <span className="inline-flex items-center gap-2">
                          <span
                            className="inline-block h-2.5 w-2.5 rounded-full"
                            style={{ backgroundColor: f.color ?? '#7a5b20' }}
                          />
                          {f.name}
                        </span>
                        <span className="text-parchment-dim">
                          {row.points}/{hoveredPlanet.claim_threshold}
                        </span>
                      </div>
                      <div className="mt-0.5 h-1.5 overflow-hidden rounded-full bg-ink">
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
              className="mt-4 inline-block text-xs text-brass hover:text-brass-bright"
            >
              View leaderboard filtered to this world →
            </Link>
          </div>
        ) : (
          <div className="text-sm text-parchment-dark">
            Hover or focus a world to see who contests it.
          </div>
        )}
      </aside>
    </div>
  );
}
