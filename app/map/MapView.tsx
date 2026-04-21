"use client";

import { useState } from "react";
import type { Planet, Faction, PlanetPoints } from "@/lib/types";

export function MapView({
  planets,
  factions,
  planetPoints,
}: {
  planets: Planet[];
  factions: Faction[];
  planetPoints: PlanetPoints[];
}) {
  const [hoverId, setHoverId] = useState<string | null>(null);
  const factionById = new Map(factions.map((f) => [f.id, f]));

  // Group points by planet
  const pointsByPlanet = new Map<string, PlanetPoints[]>();
  for (const pp of planetPoints) {
    const arr = pointsByPlanet.get(pp.planet_id) ?? [];
    arr.push(pp);
    pointsByPlanet.set(pp.planet_id, arr);
  }

  const hovered = hoverId ? planets.find((p) => p.id === hoverId) : null;
  const hoveredPoints = hovered
    ? (pointsByPlanet.get(hovered.id) ?? []).sort((a, b) => b.points - a.points)
    : [];

  return (
    <div className="grid lg:grid-cols-[1fr_320px] gap-6">
      <div className="card p-4 relative aspect-square overflow-hidden bg-gradient-to-b from-ink to-ink-2">
        <svg
          viewBox="0 0 100 100"
          className="absolute inset-0 w-full h-full"
          preserveAspectRatio="xMidYMid meet"
        >
          {/* Starfield */}
          <defs>
            <radialGradient id="sun" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="#ffcc66" />
              <stop offset="40%" stopColor="#d9a94a" />
              <stop offset="100%" stopColor="#7a5a1c" stopOpacity="0" />
            </radialGradient>
            <pattern id="stars" x="0" y="0" width="20" height="20" patternUnits="userSpaceOnUse">
              <circle cx="3" cy="7" r="0.15" fill="#e8dcc0" opacity="0.6"/>
              <circle cx="14" cy="3" r="0.1" fill="#b8a888" opacity="0.5"/>
              <circle cx="17" cy="16" r="0.12" fill="#e8dcc0" opacity="0.4"/>
              <circle cx="8" cy="14" r="0.08" fill="#b8a888" opacity="0.3"/>
            </pattern>
          </defs>
          <rect width="100" height="100" fill="url(#stars)"/>

          {/* Concentric orbital rings */}
          {[15, 25, 35, 42].map((r, i) => (
            <circle
              key={i}
              cx="50" cy="50" r={r}
              fill="none"
              stroke="#b8892d"
              strokeOpacity="0.15"
              strokeWidth="0.15"
              strokeDasharray="0.3 0.8"
            />
          ))}

          {/* Radial spokes */}
          {[0, 45, 90, 135, 180, 225, 270, 315].map((angle) => {
            const rad = (angle * Math.PI) / 180;
            return (
              <line
                key={angle}
                x1={50}
                y1={50}
                x2={50 + Math.cos(rad) * 42}
                y2={50 + Math.sin(rad) * 42}
                stroke="#b8892d"
                strokeOpacity="0.1"
                strokeWidth="0.1"
              />
            );
          })}

          {/* Central sun */}
          <circle cx="50" cy="50" r="5" fill="url(#sun)"/>
          <circle cx="50" cy="50" r="2.5" fill="#d9a94a"/>

          {/* Planets */}
          {planets.map((p) => {
            const cx = p.position_x * 100;
            const cy = p.position_y * 100;
            const controller = p.controlling_faction_id
              ? factionById.get(p.controlling_faction_id)
              : null;
            const isHover = hoverId === p.id;

            // Progress halo: total points on this planet / threshold
            const pts = pointsByPlanet.get(p.id) ?? [];
            const maxOnPlanet = Math.max(0, ...pts.map((pp) => pp.points));
            const progress = Math.min(1, maxOnPlanet / p.threshold);

            return (
              <g
                key={p.id}
                onMouseEnter={() => setHoverId(p.id)}
                onMouseLeave={() => setHoverId(null)}
                className="cursor-pointer"
              >
                {/* Progress ring */}
                {progress > 0 && !controller && (
                  <circle
                    cx={cx} cy={cy} r={3.8}
                    fill="none"
                    stroke="#d9a94a"
                    strokeOpacity="0.5"
                    strokeWidth="0.3"
                    strokeDasharray={`${progress * 23.9} 23.9`}
                    transform={`rotate(-90 ${cx} ${cy})`}
                  />
                )}
                {/* Controller ring */}
                {controller && (
                  <circle
                    cx={cx} cy={cy} r={3.8}
                    fill="none"
                    stroke={controller.color}
                    strokeWidth="0.4"
                    strokeOpacity="0.9"
                  />
                )}
                {/* Planet body */}
                <circle
                  cx={cx} cy={cy} r={isHover ? 3.2 : 2.8}
                  fill={controller?.color ?? "#4a4030"}
                  stroke="#0a0806"
                  strokeWidth="0.2"
                  style={{ transition: "r 150ms" }}
                />
                {/* Label */}
                <text
                  x={cx}
                  y={cy + 6.5}
                  fontSize="2.2"
                  fill="#e8dcc0"
                  textAnchor="middle"
                  fontFamily="Cinzel, serif"
                  letterSpacing="0.15"
                  style={{ textTransform: "uppercase" }}
                >
                  {p.name}
                </text>
              </g>
            );
          })}
        </svg>
      </div>

      {/* Side panel */}
      <div className="space-y-4">
        {hovered ? (
          <div className="card p-5">
            <div className="flex items-start justify-between gap-3">
              <h3 className="font-display text-xl text-parchment">{hovered.name}</h3>
              {hovered.controlling_faction_id ? (
                <span
                  className="text-xs font-display uppercase tracking-wider px-2 py-0.5 border"
                  style={{
                    borderColor: factionById.get(hovered.controlling_faction_id)?.color,
                    color: factionById.get(hovered.controlling_faction_id)?.color,
                  }}
                >
                  Claimed
                </span>
              ) : (
                <span className="text-xs font-display uppercase tracking-wider px-2 py-0.5 border border-parchment-dark/40 text-parchment-dark">
                  Contested
                </span>
              )}
            </div>
            {hovered.description && (
              <p className="mt-2 font-body italic text-sm text-parchment-dim leading-relaxed">
                {hovered.description}
              </p>
            )}
            <div className="mt-4 pt-4 border-t border-brass/20 text-xs uppercase tracking-wider text-parchment-dark">
              Threshold: <span className="font-display text-brass">{hovered.threshold} pts</span>
            </div>
            <div className="mt-3 space-y-2">
              {hoveredPoints.length === 0 ? (
                <div className="text-sm italic text-parchment-dark">No deeds recorded here yet.</div>
              ) : (
                hoveredPoints.map((pp) => {
                  const f = factionById.get(pp.faction_id);
                  if (!f) return null;
                  const pct = Math.min(100, (pp.points / hovered.threshold) * 100);
                  return (
                    <div key={pp.faction_id}>
                      <div className="flex justify-between text-xs font-body">
                        <span style={{ color: f.color }}>{f.name}</span>
                        <span className="text-parchment-dim">{pp.points} / {hovered.threshold}</span>
                      </div>
                      <div className="h-1 bg-ink mt-1">
                        <div
                          className="h-full transition-all"
                          style={{ width: `${pct}%`, backgroundColor: f.color }}
                        />
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        ) : (
          <div className="card p-5 text-center text-parchment-dim italic text-sm">
            Hover a world to inspect the war upon its surface.
          </div>
        )}

        <div className="card p-5">
          <div className="font-display uppercase tracking-widest text-xs text-brass mb-3">
            Legend
          </div>
          <div className="space-y-2 text-sm font-body">
            <div className="flex items-center gap-2">
              <span className="inline-block w-2.5 h-2.5 rounded-full bg-parchment-dark" />
              <span className="text-parchment-dim">Contested world</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="inline-block w-2.5 h-2.5 rounded-full" style={{ backgroundColor: "#d9a94a" }} />
              <span className="text-parchment-dim">Claimed world</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="inline-block w-3 h-3 rounded-full border border-brass-bright" />
              <span className="text-parchment-dim">Progress ring shows leading faction</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
