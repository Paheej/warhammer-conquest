"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type { Faction, GameResult, SubmissionType } from "@/lib/types";

// Shape returned by admin_rebuild_ledger / admin_correct_submission (0020).
interface LedgerDiff {
  dry_run: boolean;
  submissions_changed: number;
  elo: {
    player: string | null;
    game_system: string | null;
    faction: string | null;
    video_game: string | null;
    old_rating: number | null;
    new_rating: number | null;
    old_record: string;
    new_record: string;
  }[];
  glory: { planet: string | null; faction: string | null; old_points: number; new_points: number }[];
  control: { planet: string | null; old_controller: string | null; new_controller: string | null }[];
}

interface ApprovedRow {
  id: string;
  title: string;
  type: SubmissionType;
  player_id: string;
  faction_id: string | null;
  adversary_user_id: string | null;
  adversary_faction_id: string | null;
  opponent_name: string | null;
  result: GameResult | null;
  points: number;
  is_multiplayer: boolean;
  reviewed_at: string | null;
  profiles: { display_name: string } | null;
}

interface CorrectionForm {
  faction_id: string | null;
  adversary_faction_id: string | null;
  result: GameResult | null;
  points: number;
}

const TYPE_LABEL: Record<SubmissionType, string> = {
  game: "Battle",
  model: "Painted",
  scribe: "Scribe",
  loremaster: "Loremaster",
  bonus: "Bonus",
};

function describeError(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (err && typeof err === "object" && "message" in err) {
    return String((err as { message: unknown }).message);
  }
  return String(err);
}

function isEmpty(d: LedgerDiff) {
  return d.elo.length === 0 && d.glory.length === 0 && d.control.length === 0 && d.submissions_changed === 0;
}

function signed(n: number) {
  return n > 0 ? `+${n}` : String(n);
}

function DiffView({ diff }: { diff: LedgerDiff }) {
  if (isEmpty(diff)) {
    return (
      <div className="text-sm text-parchment-dim italic">
        The ledger already matches the records. Nothing would change.
      </div>
    );
  }
  return (
    <div className="space-y-4 text-sm">
      <div className="text-parchment-dim">
        {diff.dry_run ? "Preview — nothing has been written yet." : "Applied."}{" "}
        {diff.submissions_changed} report{diff.submissions_changed === 1 ? "" : "s"} updated (faction, result,
        points or ELO delta).
      </div>

      {diff.control.length > 0 && (
        <div>
          <div className="label">Planet control</div>
          <ul className="space-y-1">
            {diff.control.map((c, i) => (
              <li key={i} className="text-parchment">
                <span className="text-brass">{c.planet}</span>: {c.old_controller ?? "unclaimed"} →{" "}
                <span className="text-crusade">{c.new_controller ?? "unclaimed"}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {diff.elo.length > 0 && (
        <div className="overflow-x-auto">
          <div className="label">ELO</div>
          <table className="w-full text-left">
            <thead className="text-xs uppercase tracking-wider text-parchment-dark">
              <tr>
                <th className="py-1 pr-3">Player</th>
                <th className="py-1 pr-3">System</th>
                <th className="py-1 pr-3">Faction</th>
                <th className="py-1 pr-3 text-right">Rating</th>
                <th className="py-1 text-right">W-L-D</th>
              </tr>
            </thead>
            <tbody>
              {diff.elo.map((e, i) => {
                const change =
                  e.old_rating !== null && e.new_rating !== null ? e.new_rating - e.old_rating : null;
                return (
                  <tr key={i} className="border-t border-brass/10 text-parchment">
                    <td className="py-1 pr-3">{e.player ?? "?"}</td>
                    <td className="py-1 pr-3 text-parchment-dim">
                      {e.game_system}
                      {e.video_game ? ` · ${e.video_game}` : ""}
                    </td>
                    <td className="py-1 pr-3">{e.faction}</td>
                    <td className="py-1 pr-3 text-right font-mono whitespace-nowrap">
                      {e.old_rating ?? "—"} → {e.new_rating ?? "removed"}
                      {change !== null && change !== 0 && (
                        <span className={change > 0 ? "text-brass-bright" : "text-crusade"}> ({signed(change)})</span>
                      )}
                    </td>
                    <td className="py-1 text-right font-mono whitespace-nowrap text-parchment-dim">
                      {e.old_rating === null ? "—" : e.old_record} → {e.new_rating === null ? "—" : e.new_record}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {diff.glory.length > 0 && (
        <div className="overflow-x-auto">
          <div className="label">Planet glory</div>
          <table className="w-full text-left">
            <tbody>
              {diff.glory.map((g, i) => (
                <tr key={i} className="border-t border-brass/10 text-parchment">
                  <td className="py-1 pr-3 text-brass">{g.planet}</td>
                  <td className="py-1 pr-3">{g.faction}</td>
                  <td className="py-1 text-right font-mono whitespace-nowrap">
                    {g.old_points} → {g.new_points}{" "}
                    <span className={g.new_points > g.old_points ? "text-brass-bright" : "text-crusade"}>
                      ({signed(g.new_points - g.old_points)})
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

export function AdminLedger({ factions }: { factions: Faction[] }) {
  const router = useRouter();
  const sortedFactions = useMemo(() => [...factions].sort((a, b) => a.name.localeCompare(b.name)), [factions]);
  const factionName = useMemo(() => new Map(factions.map((f) => [f.id, f.name])), [factions]);

  // ---- correction state ----
  const [rows, setRows] = useState<ApprovedRow[] | null>(null);
  const [playerNames, setPlayerNames] = useState<Map<string, string>>(new Map());
  const [loadError, setLoadError] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<ApprovedRow | null>(null);
  const [form, setForm] = useState<CorrectionForm | null>(null);
  const [preview, setPreview] = useState<LedgerDiff | null>(null);
  const [applied, setApplied] = useState<LedgerDiff | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // ---- full rebuild state ----
  const [fullPreview, setFullPreview] = useState<LedgerDiff | null>(null);
  const [fullApplied, setFullApplied] = useState<LedgerDiff | null>(null);
  const [fullBusy, setFullBusy] = useState(false);
  const [fullError, setFullError] = useState<string | null>(null);

  async function loadRows() {
    setLoadError(null);
    const supabase = createClient();
    const [{ data, error: err }, { data: players }] = await Promise.all([
      supabase
        .from("submissions")
        .select(
          "id, title, type, player_id, faction_id, adversary_user_id, adversary_faction_id, opponent_name, result, points, is_multiplayer, reviewed_at, profiles!submissions_player_id_fkey(display_name)",
        )
        .eq("status", "approved")
        .is("mirror_of", null)
        .order("reviewed_at", { ascending: false }),
      supabase.from("searchable_players").select("id, display_name"),
    ]);
    if (err) {
      setLoadError(err.message);
      return;
    }
    setRows((data ?? []) as unknown as ApprovedRow[]);
    setPlayerNames(new Map((players ?? []).map((p) => [p.id as string, p.display_name as string])));
  }

  useEffect(() => {
    loadRows();
  }, []);

  const matches = useMemo(() => {
    if (!rows) return [];
    const q = query.trim().toLowerCase();
    const filtered = q
      ? rows.filter(
          (r) =>
            r.title.toLowerCase().includes(q) ||
            (r.profiles?.display_name ?? "").toLowerCase().includes(q) ||
            (r.opponent_name ?? "").toLowerCase().includes(q),
        )
      : rows;
    return filtered.slice(0, 15);
  }, [rows, query]);

  function select(r: ApprovedRow) {
    setSelected(r);
    setForm({
      faction_id: r.faction_id,
      adversary_faction_id: r.adversary_faction_id,
      result: r.result,
      points: r.points,
    });
    setPreview(null);
    setApplied(null);
    setError(null);
  }

  function patch(p: Partial<CorrectionForm>) {
    setForm((f) => (f ? { ...f, ...p } : f));
    setPreview(null); // any edit invalidates the preview
  }

  const formChanged =
    !!selected &&
    !!form &&
    (form.faction_id !== selected.faction_id ||
      form.adversary_faction_id !== selected.adversary_faction_id ||
      form.result !== selected.result ||
      form.points !== selected.points);

  async function runCorrection(dryRun: boolean) {
    if (!selected || !form) return;
    setBusy(true);
    setError(null);
    try {
      const supabase = createClient();
      const { data, error: err } = await supabase.rpc("admin_correct_submission", {
        p_submission_id: selected.id,
        p_faction_id: form.faction_id,
        p_adversary_faction_id: form.adversary_faction_id,
        p_result: form.result,
        p_points: form.points,
        p_dry_run: dryRun,
      });
      if (err) throw err;
      if (dryRun) {
        setPreview(data as LedgerDiff);
      } else {
        setApplied(data as LedgerDiff);
        setPreview(null);
        setSelected(null);
        setForm(null);
        await loadRows();
        router.refresh();
      }
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  }

  async function runFull(dryRun: boolean) {
    setFullBusy(true);
    setFullError(null);
    try {
      const supabase = createClient();
      const { data, error: err } = await supabase.rpc("admin_rebuild_ledger", { p_dry_run: dryRun });
      if (err) throw err;
      if (dryRun) {
        setFullPreview(data as LedgerDiff);
        setFullApplied(null);
      } else {
        setFullApplied(data as LedgerDiff);
        setFullPreview(null);
        await loadRows();
        router.refresh();
      }
    } catch (e) {
      setFullError(describeError(e));
    } finally {
      setFullBusy(false);
    }
  }

  const linked = !!selected?.adversary_user_id;
  const isGame = selected?.type === "game";

  return (
    <div className="space-y-4">
      {/* ---------- Correct one report ---------- */}
      <div className="card p-6 space-y-4">
        <div>
          <div className="font-display text-parchment">Correct an Approved Report</div>
          <p className="text-sm text-parchment-dim font-body italic mt-1">
            Fix a faction, result or points on a report that has already been approved. The whole campaign is then
            replayed in approval order, so ELO, planet glory, planet control and the opponent&apos;s mirrored report all
            line up. Preview first; nothing is written until you apply.
          </p>
        </div>

        {loadError && <div className="text-sm text-blood">{loadError}</div>}

        {!selected && (
          <div className="space-y-2">
            <input
              type="text"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search by player, title or opponent…"
              className="input w-full"
            />
            {rows === null ? (
              <div className="text-sm text-parchment-dim italic">Loading the archives…</div>
            ) : matches.length === 0 ? (
              <div className="text-sm text-parchment-dim italic">No approved reports match.</div>
            ) : (
              <ul className="divide-y divide-brass/10 border border-brass/10">
                {matches.map((r) => (
                  <li key={r.id}>
                    <button
                      type="button"
                      onClick={() => select(r)}
                      className="w-full text-left px-3 py-2 hover:bg-brass/5 flex flex-wrap items-baseline gap-x-3 gap-y-1"
                    >
                      <span className="text-xs uppercase tracking-wider text-parchment-dark w-20 shrink-0">
                        {TYPE_LABEL[r.type]}
                      </span>
                      <span className="text-parchment flex-1 min-w-0 truncate">{r.title}</span>
                      <span className="text-sm text-parchment-dim">
                        {r.profiles?.display_name ?? "?"} · {r.faction_id ? factionName.get(r.faction_id) : "no faction"}
                        {r.result ? ` · ${r.result}` : ""} · {r.points} pts
                        {r.reviewed_at ? ` · ${new Date(r.reviewed_at).toLocaleDateString()}` : ""}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}

        {selected && form && (
          <div className="rounded border border-brass/20 bg-ink/40 p-4 space-y-4">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <div className="text-xs uppercase tracking-wider text-parchment-dark">{TYPE_LABEL[selected.type]}</div>
                <div className="font-display text-lg text-parchment">{selected.title}</div>
                <div className="text-sm text-parchment-dim">
                  by {selected.profiles?.display_name ?? "?"}
                  {linked && <> · vs {playerNames.get(selected.adversary_user_id!) ?? "linked player"}</>}
                  {!linked && selected.opponent_name && <> · vs {selected.opponent_name} (unlinked)</>}
                </div>
              </div>
              <button
                type="button"
                onClick={() => {
                  setSelected(null);
                  setForm(null);
                  setPreview(null);
                  setError(null);
                }}
                className="btn-ghost text-sm"
                disabled={busy}
              >
                Choose another
              </button>
            </div>

            <div className="grid sm:grid-cols-2 md:grid-cols-4 gap-4">
              <div>
                <label className="label">Faction</label>
                <select
                  value={form.faction_id ?? ""}
                  onChange={(e) => patch({ faction_id: e.target.value || null })}
                  className="input w-full"
                >
                  <option value="" className="bg-ink text-parchment">
                    (no faction)
                  </option>
                  {sortedFactions.map((f) => (
                    <option key={f.id} value={f.id} className="bg-ink text-parchment">
                      {f.name}
                    </option>
                  ))}
                </select>
              </div>

              {isGame && linked && (
                <div>
                  <label className="label">Opponent faction</label>
                  <select
                    value={form.adversary_faction_id ?? ""}
                    onChange={(e) => patch({ adversary_faction_id: e.target.value || null })}
                    className="input w-full"
                  >
                    {sortedFactions.map((f) => (
                      <option key={f.id} value={f.id} className="bg-ink text-parchment">
                        {f.name}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              {isGame && (
                <div>
                  <label className="label">Result</label>
                  <select
                    value={form.result ?? ""}
                    onChange={(e) => patch({ result: e.target.value as GameResult })}
                    className="input w-full"
                  >
                    {(["win", "loss", "draw"] as const).map((r) => (
                      <option key={r} value={r} className="bg-ink text-parchment">
                        {r}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              <div>
                <label className="label">Points</label>
                <input
                  type="number"
                  min={0}
                  value={form.points}
                  onChange={(e) => patch({ points: Math.max(0, Number(e.target.value) || 0) })}
                  className="input w-full"
                />
              </div>
            </div>

            {selected.is_multiplayer && (
              <div className="text-xs text-parchment-dim italic">
                Multiplayer report: the roster&apos;s factions aren&apos;t editable here, only the submitter&apos;s.
              </div>
            )}

            {error && <div className="text-sm text-blood">{error}</div>}

            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                onClick={() => runCorrection(true)}
                disabled={busy || !formChanged}
                className="btn-primary disabled:opacity-40 disabled:cursor-not-allowed"
              >
                {busy && !preview ? "Consulting the archives…" : "Preview Recalculation"}
              </button>
              {preview && (
                <button
                  type="button"
                  onClick={() => runCorrection(false)}
                  disabled={busy}
                  className="btn-danger disabled:opacity-40"
                >
                  {busy ? "Rewriting history…" : "Apply Correction"}
                </button>
              )}
            </div>

            {preview && <DiffView diff={preview} />}
          </div>
        )}

        {applied && (
          <div className="rounded border border-brass/30 p-4">
            <DiffView diff={applied} />
          </div>
        )}
      </div>

      {/* ---------- Full rebuild ---------- */}
      <div className="card p-6 space-y-4">
        <div>
          <div className="font-display text-parchment">Recalculate Entire Ledger</div>
          <p className="text-sm text-parchment-dim font-body italic mt-1">
            Replays every approved report in approval order and rebuilds ELO, planet glory and planet control from
            scratch. Use it after editing a report by hand, or to check the ledger hasn&apos;t drifted. Manually
            assigned planet controllers not backed by glory will be cleared. Awards already granted are kept.
          </p>
        </div>
        {fullError && <div className="text-sm text-blood">{fullError}</div>}
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => runFull(true)}
            disabled={fullBusy}
            className="btn-primary disabled:opacity-40"
          >
            {fullBusy && !fullPreview ? "Consulting the archives…" : "Preview Recalculation"}
          </button>
          {fullPreview && !isEmpty(fullPreview) && (
            <button
              type="button"
              onClick={() => runFull(false)}
              disabled={fullBusy}
              className="btn-danger disabled:opacity-40"
            >
              {fullBusy ? "Rewriting history…" : "Apply Recalculation"}
            </button>
          )}
        </div>
        {fullPreview && <DiffView diff={fullPreview} />}
        {fullApplied && <DiffView diff={fullApplied} />}
      </div>
    </div>
  );
}
