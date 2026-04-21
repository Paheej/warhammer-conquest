import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { MapView } from "./MapView";
import type { Planet, Faction, PlanetPoints } from "@/lib/types";

export const dynamic = "force-dynamic";

export default async function MapPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/auth/login");

  const [
    { data: planets },
    { data: factions },
    { data: planetPoints },
  ] = await Promise.all([
    supabase.from("planets").select("*"),
    supabase.from("factions").select("*"),
    supabase.from("planet_points").select("*"),
  ]);

  return (
    <div className="fade-up">
      <div className="text-center mb-6">
        <div className="text-brass text-3xl mb-2">✠</div>
        <h1 className="font-display text-4xl tracking-widest text-parchment">
          THE CAMPAIGN MAP
        </h1>
        <p className="mt-2 font-body italic text-parchment-dim">
          Hover a world to see the struggle for its surface.
        </p>
      </div>

      <MapView
        planets={(planets ?? []) as Planet[]}
        factions={(factions ?? []) as Faction[]}
        planetPoints={(planetPoints ?? []) as PlanetPoints[]}
      />
    </div>
  );
}
