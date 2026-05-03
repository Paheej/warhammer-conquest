"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type { Submission, Planet, Faction } from "@/lib/types";

type Row = Submission & { profiles: { display_name: string } | null };

export function AdminQueue({
  submissions,
  planets,
  factions,
}: {
  submissions: Row[];
  planets: Planet[];
  factions: Faction[];
}) {
  const router = useRouter();
  const [workingId, setWorkingId] = useState<string | null>(null);
  const [adjustments, setAdjustments] = useState<Record<string, number>>({});
  const [notes, setNotes] = useState<Record<string, string>>({});

  const planetById = new Map(planets.map((p) => [p.id, p]));
  const factionById = new Map(factions.map((f) => [f.id, f]));

  async function review(id: string, status: "approved" | "rejected") {
    setWorkingId(id);
    const supabase = createClient();

    const { data: { user } } = await supabase.auth.getUser();
    const finalPoints = adjustments[id];
    const reviewNote = notes[id] || null;

    const update: Record<string, unknown> = {
      status,
      reviewed_by: user?.id ?? null,
      reviewed_at: new Date().toISOString(),
      review_notes: reviewNote,
    };
    if (status === "approved" && typeof finalPoints === "number") {
      update.points = finalPoints;
    }

    const { error } = await supabase
      .from("submissions")
      .update(update)
      .eq("id", id);

    setWorkingId(null);
    if (error) {
      alert(error.message);
      return;
    }
    router.refresh();
  }

  if (submissions.length === 0) {
    return (
      <div className="card p-10 text-center text-parchment-dim italic">
        The queue is silent. All deeds have been judged.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {submissions.map((s) => {
        const planet = s.target_planet_id ? planetById.get(s.target_planet_id) : null;
        const faction = s.faction_id ? factionById.get(s.faction_id) : null;
        const adjusted = adjustments[s.id] ?? s.points;

        return (
          <div key={s.id} className="card p-6">
            <div className="flex flex-wrap items-start justify-between gap-4 mb-4">
              <div>
                <div className="flex items-center gap-3 mb-1 flex-wrap">
                  <span className="font-display text-xs uppercase tracking-widest text-brass px-2 py-0.5 border border-brass/40">
                    {s.type}
                  </span>
                  {s.type === "game" && s.result && (
                    <span
                      className={`font-display text-xs uppercase tracking-widest px-2 py-0.5 border ${
                        s.result === "win"
                          ? "border-brass-bright text-brass-bright"
                          : s.result === "loss"
                          ? "border-crusade text-crusade"
                          : "border-parchment-dim text-parchment-dim"
                      }`}
                    >
                      {s.result}
                    </span>
                  )}
                  {s.type === "loremaster" && s.lore_format && (
                    <span className="inline-flex items-center gap-1 rounded-full border border-indigo-700/60 bg-indigo-900/30 px-2 py-0.5 text-xs font-medium text-indigo-200">
                      <span aria-hidden>{s.lore_format === "novel" ? "📕" : "🎧"}</span>
                      {s.lore_format === "novel" ? "Novel" : "Audiobook"}
                    </span>
                  )}
                  {s.type === "loremaster" && s.lore_rating !== null && (
                    <span className="text-sm text-brass-bright" aria-label={`${s.lore_rating} out of 5`}>
                      {Array.from({ length: 5 }).map((_, i) => (i < (s.lore_rating ?? 0) ? "★" : "☆")).join("")}
                    </span>
                  )}
                </div>
                <h3 className="font-display text-xl text-parchment">{s.title}</h3>
                <div className="mt-1 text-sm text-parchment-dim font-body">
                  by <span className="text-parchment">{s.profiles?.display_name ?? "Unknown"}</span>
                  {faction && <> · <span style={{ color: faction.color }}>{faction.name}</span></>}
                  {planet && <> · targeting <span className="text-brass">{planet.name}</span></>}
                  {s.opponent_name && <> · vs {s.opponent_name}</>}
                </div>
              </div>
              <div className="text-right">
                <div className="text-xs text-parchment-dark uppercase tracking-wider">Claimed</div>
                <div className="font-display text-2xl text-brass-bright">{s.points}</div>
              </div>
            </div>

            {s.body && (
              <div className="mb-4 p-4 bg-ink border border-brass/10 font-body text-parchment-dim whitespace-pre-wrap max-h-48 overflow-y-auto">
                {s.body}
              </div>
            )}

            {s.image_url && (
              /* eslint-disable-next-line @next/next/no-img-element */
              <img
                src={s.image_url}
                alt={s.title}
                className="mb-4 max-h-80 border border-brass/20"
              />
            )}

            <div className="grid md:grid-cols-2 gap-4 pt-4 border-t border-brass/10">
              <div>
                <label className="label">Adjust Points</label>
                <input
                  type="number"
                  min={0}
                  value={adjusted}
                  onChange={(e) =>
                    setAdjustments((a) => ({
                      ...a,
                      [s.id]: Number(e.target.value),
                    }))
                  }
                  className="input w-full"
                />
              </div>
              <div>
                <label className="label">Review Notes (optional)</label>
                <input
                  type="text"
                  value={notes[s.id] ?? ""}
                  onChange={(e) =>
                    setNotes((n) => ({ ...n, [s.id]: e.target.value }))
                  }
                  className="input w-full"
                  placeholder="Reason for rejection, or a commendation…"
                />
              </div>
            </div>

            <div className="flex gap-3 justify-end mt-4">
              <button
                onClick={() => review(s.id, "rejected")}
                disabled={workingId === s.id}
                className="btn-danger disabled:opacity-50"
              >
                Reject
              </button>
              <button
                onClick={() => review(s.id, "approved")}
                disabled={workingId === s.id}
                className="btn-primary disabled:opacity-50"
              >
                {workingId === s.id ? "Sealing…" : "Approve"}
              </button>
            </div>
          </div>
        );
      })}
    </div>
  );
}
