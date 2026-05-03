import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import HonoursBadgeRow, { type HonourBadge } from "@/components/HonoursBadgeRow";
import type { AwardTier, FactionTotal, PlayerTotal } from "@/lib/types";

export const dynamic = "force-dynamic";

interface PageProps {
  searchParams: Promise<{ faction?: string }>;
}

export default async function LeaderboardPage({ searchParams }: PageProps) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/auth/login");

  const { faction: factionFilter } = await searchParams;

  const [{ data: factions }, { data: players }] = await Promise.all([
    supabase
      .from("faction_totals")
      .select("*")
      .order("total_points", { ascending: false }),
    supabase
      .from("player_totals")
      .select("*")
      .order("total_points", { ascending: false }),
  ]);
  const ft = (factions ?? []) as FactionTotal[];
  const allPlayers = (players ?? []) as PlayerTotal[];

  let pt: PlayerTotal[];
  if (factionFilter) {
    // Find the set of players with at least one approved deed aligned to the
    // selected faction, then keep their full leaderboard rows. Totals match
    // the unfiltered view — we only narrow *who* shows up. (Aggregating in
    // JS / a one-shot id query avoids a dedicated view.)
    const { data: aligned } = await supabase
      .from("submissions")
      .select("player_id")
      .eq("status", "approved")
      .eq("faction_id", factionFilter);

    const ids = new Set((aligned ?? []).map((r) => r.player_id as string));
    pt = allPlayers.filter((p) => ids.has(p.player_id)).slice(0, 50);
  } else {
    pt = allPlayers.slice(0, 50);
  }

  const activeFaction = factionFilter ? ft.find((f) => f.faction_id === factionFilter) : null;

  // Honours for visible commanders. Pinned first, then by rarity descending.
  const honoursByPlayer = new Map<string, HonourBadge[]>();
  if (pt.length > 0) {
    const { data: rawHonours } = await supabase
      .from("player_awards")
      .select("id, player_id, is_featured, awards(name, icon, tier)")
      .in("player_id", pt.map((p) => p.player_id));

    type HonourRow = {
      id: string;
      player_id: string;
      is_featured: boolean;
      awards: { name: string; icon: string; tier: AwardTier } | null;
    };

    const TIER_RANK: Record<AwardTier, number> = {
      adamantium: 0,
      legendary:  1,
      honoured:   2,
      common:     3,
    };

    for (const r of (rawHonours ?? []) as unknown as HonourRow[]) {
      if (!r.awards) continue;
      const list = honoursByPlayer.get(r.player_id) ?? [];
      list.push({
        player_award: { id: r.id, is_featured: r.is_featured },
        award: r.awards,
      });
      honoursByPlayer.set(r.player_id, list);
    }

    for (const list of honoursByPlayer.values()) {
      list.sort((a, b) => {
        if (a.player_award.is_featured !== b.player_award.is_featured) {
          return a.player_award.is_featured ? -1 : 1;
        }
        return TIER_RANK[a.award.tier] - TIER_RANK[b.award.tier];
      });
    }
  }

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
                <th className="text-right p-3 hidden md:table-cell">Painted Units</th>
                <th className="text-right p-3 hidden md:table-cell">Tales</th>
                <th className="text-right p-3 hidden md:table-cell">Lore Read</th>
                <th className="text-right p-3 hidden sm:table-cell">Worlds</th>
                <th className="text-right p-3">Glory</th>
              </tr>
            </thead>
            <tbody>
              {ft.map((f, i) => {
                const isActive = factionFilter === f.faction_id;
                return (
                  <tr
                    key={f.faction_id}
                    className={`border-b border-brass/5 transition-colors ${
                      isActive ? "bg-brass/10" : "hover:bg-brass/5"
                    }`}
                  >
                    <td className="p-3 font-display text-brass">{i + 1}</td>
                    <td className="p-3">
                      <Link
                        href={isActive ? "/leaderboard" : `/leaderboard?faction=${f.faction_id}`}
                        aria-label={
                          isActive
                            ? `Clear faction filter`
                            : `Filter commanders by ${f.faction_name}`
                        }
                        className="flex items-center gap-3 text-parchment transition-colors hover:text-brass-bright"
                      >
                        <span
                          className="inline-block w-1 h-8"
                          style={{ backgroundColor: f.color }}
                        />
                        <span className="font-display">{f.faction_name}</span>
                      </Link>
                    </td>
                    <td className="p-3 text-right font-body hidden sm:table-cell">{f.wins}</td>
                    <td className="p-3 text-right font-body hidden md:table-cell">{f.models_painted}</td>
                    <td className="p-3 text-right font-body hidden md:table-cell">{f.lore_written}</td>
                    <td className="p-3 text-right font-body hidden md:table-cell">{f.lore_read}</td>
                    <td className="p-3 text-right font-body hidden sm:table-cell">{f.planets_controlled}</td>
                    <td className="p-3 text-right font-display text-brass-bright">{f.total_points}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <div className="mb-4 flex flex-wrap items-center gap-3">
          <h2 className="font-display text-xl tracking-widest text-parchment">
            COMMANDERS
          </h2>
          {activeFaction && (
            <span className="inline-flex items-center gap-2 rounded-full border border-brass/40 bg-brass/10 px-3 py-0.5 text-xs">
              <span
                className="inline-block h-2 w-2 rounded-full"
                style={{ backgroundColor: activeFaction.color }}
              />
              <span className="text-parchment">
                Aligned to <span className="font-display">{activeFaction.faction_name}</span>
              </span>
              <Link
                href="/leaderboard"
                aria-label="Clear faction filter"
                className="text-parchment-dim hover:text-brass-bright"
              >
                ✕
              </Link>
            </span>
          )}
        </div>
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
              {pt.length === 0 ? (
                <tr>
                  <td colSpan={5} className="p-6 text-center text-parchment-dim italic">
                    {activeFaction
                      ? `No commanders have rallied to ${activeFaction.faction_name} yet.`
                      : "No commanders yet."}
                  </td>
                </tr>
              ) : (
                pt.map((p, i) => {
                  const honours = honoursByPlayer.get(p.player_id) ?? [];
                  return (
                    <tr key={p.player_id} className="border-b border-brass/5 hover:bg-brass/5">
                      <td className="p-3 font-display text-brass">{i + 1}</td>
                      <td className="p-3 font-display">
                        <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                          <Link
                            href={`/player/${p.player_id}`}
                            className="text-parchment hover:text-brass-bright transition-colors"
                          >
                            {p.display_name}
                          </Link>
                          <HonoursBadgeRow badges={honours} />
                        </div>
                      </td>
                      <td className="p-3 hidden sm:table-cell" style={{ color: p.faction_color ?? "#b8a888" }}>
                        {p.faction_name ?? "—"}
                      </td>
                      <td className="p-3 text-right font-body hidden sm:table-cell">{p.approved_count}</td>
                      <td className="p-3 text-right font-display text-brass-bright">{p.total_points}</td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
