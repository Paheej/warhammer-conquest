import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import type { FactionTotal, Planet, Faction } from "@/lib/types";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  const supabase = await createClient();

  const [{ data: factionTotals }, { data: planets }, { data: factions }] =
    await Promise.all([
      supabase
        .from("faction_totals")
        .select("*")
        .order("total_points", { ascending: false })
        .limit(5),
      supabase.from("planets").select("*"),
      supabase.from("factions").select("*"),
    ]);

  const totals = (factionTotals ?? []) as FactionTotal[];
  const factionMap = new Map<string, Faction>(
    (factions ?? []).map((f: Faction) => [f.id, f])
  );
  const claimedCount = (planets ?? []).filter(
    (p: Planet) => p.controlling_faction_id
  ).length;

  return (
    <div className="space-y-16">
      {/* Hero */}
      <section className="text-center py-12 fade-up">
        <div className="text-brass text-5xl mb-4">✠</div>
        <h1 className="font-display text-5xl md:text-7xl text-parchment tracking-[0.15em]">
          CAMPAIGN OF THE
          <br />
          <span className="text-brass-bright italic font-gothic text-6xl md:text-8xl tracking-normal">
            Burning Star
          </span>
        </h1>
        <div className="divider-ornate mt-8 max-w-2xl mx-auto">
          <span>An Account of War</span>
        </div>
        <p className="mt-6 max-w-2xl mx-auto text-lg font-body italic text-parchment-dim leading-relaxed">
          Four worlds burn. Eight factions contend. Every painted model, every battle
          fought, every tale told is carved into the eternal record of this crusade.
        </p>
        <div className="mt-10 flex gap-4 justify-center flex-wrap">
          <Link href="/map" className="btn-primary">
            View the Map
          </Link>
          <Link href="/submit" className="btn-ghost">
            Log a Deed
          </Link>
        </div>
      </section>

      {/* Stats strip */}
      <section className="grid grid-cols-2 md:grid-cols-4 gap-px bg-brass/20 border border-brass/20">
        <Stat label="Worlds in Contention" value={String(planets?.length ?? 0)} />
        <Stat label="Worlds Claimed" value={String(claimedCount)} />
        <Stat label="Factions Vying" value={String(factions?.length ?? 0)} />
        <Stat
          label="Total Glory"
          value={String(totals.reduce((s, t) => s + t.total_points, 0))}
        />
      </section>

      {/* Faction leaderboard */}
      <section>
        <div className="flex items-center justify-between mb-6">
          <h2 className="font-display text-2xl tracking-widest text-parchment">
            ORDER OF PRECEDENCE
          </h2>
          <Link
            href="/leaderboard"
            className="text-sm text-brass hover:text-brass-bright font-display uppercase tracking-wider"
          >
            Full Ledger →
          </Link>
        </div>

        {totals.length === 0 ? (
          <div className="card p-8 text-center text-parchment-dim italic">
            No deeds have been recorded. The war has yet to begin.
          </div>
        ) : (
          <div className="space-y-3">
            {totals.map((t, i) => (
              <FactionRow key={t.faction_id} rank={i + 1} total={t} />
            ))}
          </div>
        )}
      </section>

      {/* Planet status */}
      <section>
        <h2 className="font-display text-2xl tracking-widest text-parchment mb-6">
          WORLDS OF THE CRUSADE
        </h2>
        <div className="grid md:grid-cols-2 gap-4">
          {(planets ?? []).map((p: Planet) => {
            const controller = p.controlling_faction_id
              ? factionMap.get(p.controlling_faction_id)
              : null;
            return (
              <div key={p.id} className="card p-6">
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <h3 className="font-display text-xl text-parchment">{p.name}</h3>
                    <p className="mt-2 text-parchment-dim font-body italic text-sm leading-relaxed">
                      {p.description}
                    </p>
                  </div>
                  {controller ? (
                    <div
                      className="shrink-0 px-3 py-1 text-xs font-display uppercase tracking-wider border"
                      style={{
                        borderColor: controller.color,
                        color: controller.color,
                      }}
                    >
                      Claimed
                    </div>
                  ) : (
                    <div className="shrink-0 px-3 py-1 text-xs font-display uppercase tracking-wider border border-parchment-dark/30 text-parchment-dark">
                      Contested
                    </div>
                  )}
                </div>
                <div className="mt-4 pt-4 border-t border-brass/10 flex items-center justify-between">
                  <span className="text-xs text-parchment-dark uppercase tracking-wider">
                    Threshold
                  </span>
                  <span className="font-display text-brass">{p.threshold} pts</span>
                </div>
              </div>
            );
          })}
        </div>
      </section>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-ink p-6 text-center">
      <div className="font-display text-4xl text-brass-bright">{value}</div>
      <div className="mt-1 font-display uppercase tracking-widest text-xs text-parchment-dark">
        {label}
      </div>
    </div>
  );
}

function FactionRow({ rank, total }: { rank: number; total: FactionTotal }) {
  return (
    <div className="card p-4 flex items-center gap-4">
      <div className="w-10 text-center font-display text-3xl text-brass">
        {rank === 1 ? "I" : rank === 2 ? "II" : rank === 3 ? "III" : rank === 4 ? "IV" : "V"}
      </div>
      <div
        className="w-1 h-12 rounded-full"
        style={{ backgroundColor: total.color }}
      />
      <div className="flex-1">
        <div className="font-display text-lg text-parchment">
          {total.faction_name}
        </div>
        <div className="text-xs text-parchment-dark font-body">
          {total.wins} victories · {total.models_painted} models · {total.lore_submitted} tales · {total.planets_controlled} worlds
        </div>
      </div>
      <div className="text-right">
        <div className="font-display text-2xl text-brass-bright">
          {total.total_points}
        </div>
        <div className="text-xs uppercase tracking-wider text-parchment-dark">
          glory
        </div>
      </div>
    </div>
  );
}
