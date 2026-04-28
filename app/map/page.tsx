// =====================================================================
// app/map/page.tsx — REPLACEMENT map page.
//
// Renders each planet as a circle on a starfield. When planet.image_url
// is set, the circle is filled with that image. Fully responsive —
// the map uses an aspect-ratio container that scales down on mobile.
//
// The hover panel (contesting factions, points vs threshold) is lifted
// into the client <OrbitalMap> component.
// =====================================================================

import { createClient } from '@/lib/supabase/server';
import OrbitalMap from './OrbitalMap';

export const revalidate = 30;

export interface MapPlanet {
  id: string;
  name: string;
  description: string | null;
  position_x: number | null;
  position_y: number | null;
  claim_threshold: number;
  image_url: string | null;
  controlling_faction_id: string | null;
}

export interface MapPoint {
  planet_id: string;
  faction_id: string;
  points: number;
}

export interface MapFaction {
  id: string;
  name: string;
  color: string | null;
}

export default async function MapPage() {
  const supabase = await createClient();
  const [pRes, ppRes, fRes] = await Promise.all([
    supabase.from('planets').select('id, name, description, position_x, position_y, claim_threshold:threshold, image_url, controlling_faction_id'),
    supabase.from('planet_points').select('planet_id, faction_id, points'),
    supabase.from('factions').select('id, name, color'),
  ]);

  const planets  = (pRes.data ?? [])  as MapPlanet[];
  const points   = (ppRes.data ?? []) as MapPoint[];
  const factions = (fRes.data ?? [])  as MapFaction[];

  return (
    <main className="mx-auto max-w-6xl px-4 py-6 sm:px-6 sm:py-10">
      <header className="mb-6">
        <p className="font-cinzel text-xs uppercase tracking-[0.3em] text-brass-300">
          ✠ Orbital Chart ✠
        </p>
        <h1 className="mt-1 font-cinzel text-3xl text-brass-100">The Theatre of War</h1>
        <p className="mt-2 text-sm text-parchment-300">
          Hover a world to see which factions contest it. The banner of the dominant faction
          flies over each planet claimed.
        </p>
      </header>

      <OrbitalMap planets={planets} points={points} factions={factions} />
    </main>
  );
}
