import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { FactionTotal, PlayerTotal } from "@/lib/types";

export const dynamic = "force-dynamic";

export default async function LeaderboardPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/auth/login");

  const [{ data: factions }, { data: players }] = await Promise.all([
    supabase
      .from("faction_totals")
      .select("*")
      .order("total_points", { ascending: false }),
    supabase
      .from("player_totals")
      .select("*")
      .order("total_points", { ascending: false })
      .limit(50),
  ]);

  const ft = (factions ?? []) as FactionTotal[];
  const pt = (players ?? []) as PlayerTotal[];

  return (
    <div className="space-y-12 fade-up">
      <div className="text-center">
        <div className="text-brass text-3xl mb-2">✠</div>
        <h1 className="font-display text-4xl tracking-widest text-parchment">
          THE ETERNAL LEDGER
        </h1>
        <p className="mt-2 font-body italic text-parchment-dim">
          Glory, measured and remembered.
        </p>
      </div>

      <section>
        <h2 className="font-display text-xl tracking-widest text-parchment mb-4">
          FACTIONS
        </h2>
        <div className="card overflow-hidden">
          <table className="w-full">
            <thead>
              <tr className="border-b border-brass/20 text-xs font-display uppercase tracking-wider text-brass">
                <th className="text-left p-3 w-12">#</th>
                <th className="text-left p-3">Faction</th>
                <th className="text-right p-3 hidden sm:table-cell">Wins</th>
                <th className="text-right p-3 hidden md:table-cell">Models</th>
                <th className="text-right p-3 hidden md:table-cell">Tales</th>
                <th className="text-right p-3 hidden sm:table-cell">Worlds</th>
                <th className="text-right p-3">Glory</th>
              </tr>
            </thead>
            <tbody>
              {ft.map((f, i) => (
                <tr key={f.faction_id} className="border-b border-brass/5 hover:bg-brass/5">
                  <td className="p-3 font-display text-brass">{i + 1}</td>
                  <td className="p-3">
                    <div className="flex items-center gap-3">
                      <span
                        className="inline-block w-1 h-8"
                        style={{ backgroundColor: f.color }}
                      />
                      <span className="font-display text-parchment">{f.faction_name}</span>
                    </div>
                  </td>
                  <td className="p-3 text-right font-body hidden sm:table-cell">{f.wins}</td>
                  <td className="p-3 text-right font-body hidden md:table-cell">{f.models_painted}</td>
                  <td className="p-3 text-right font-body hidden md:table-cell">{f.lore_submitted}</td>
                  <td className="p-3 text-right font-body hidden sm:table-cell">{f.planets_controlled}</td>
                  <td className="p-3 text-right font-display text-brass-bright">{f.total_points}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <h2 className="font-display text-xl tracking-widest text-parchment mb-4">
          COMMANDERS
        </h2>
        <div className="card overflow-hidden">
          <table className="w-full">
            <thead>
              <tr className="border-b border-brass/20 text-xs font-display uppercase tracking-wider text-brass">
                <th className="text-left p-3 w-12">#</th>
                <th className="text-left p-3">Name</th>
                <th className="text-left p-3 hidden sm:table-cell">Faction</th>
                <th className="text-right p-3 hidden sm:table-cell">Deeds</th>
                <th className="text-right p-3">Glory</th>
              </tr>
            </thead>
            <tbody>
              {pt.map((p, i) => (
                <tr key={p.player_id} className="border-b border-brass/5 hover:bg-brass/5">
                  <td className="p-3 font-display text-brass">{i + 1}</td>
                  <td className="p-3 font-display">
                    <Link
                      href={`/player/${p.player_id}`}
                      className="text-parchment hover:text-brass-bright transition-colors"
                    >
                      {p.display_name}
                    </Link>
                  </td>
                  <td className="p-3 hidden sm:table-cell" style={{ color: p.faction_color ?? "#b8a888" }}>
                    {p.faction_name ?? "—"}
                  </td>
                  <td className="p-3 text-right font-body hidden sm:table-cell">{p.approved_count}</td>
                  <td className="p-3 text-right font-display text-brass-bright">{p.total_points}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
