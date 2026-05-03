"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

const EXPORT_TABLES = [
  "profiles",
  "factions",
  "planets",
  "planet_points",
  "planet_flip_log",
  "submissions",
  "awards",
  "player_awards",
  "elo_ratings",
  "elo_config",
  "player_factions",
  "game_systems",
  "point_schemes",
  "video_game_titles",
  "planet_game_systems",
] as const;

const EXPORT_VIEWS = ["faction_totals", "player_totals"] as const;

const CONFIRM_WORDS = ["CLEAR", "DELETE"];

function describeError(err: unknown): string {
  if (err instanceof Error) return err.message;
  if (err && typeof err === "object") {
    const o = err as Record<string, unknown>;
    const parts = [o.message, o.details, o.hint, o.code]
      .filter((x): x is string => typeof x === "string" && x.length > 0);
    if (parts.length > 0) return parts.join(" — ");
    try {
      return JSON.stringify(err);
    } catch {
      return String(err);
    }
  }
  return String(err);
}

export function AdminSeason() {
  const router = useRouter();

  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);

  const [confirmOpen, setConfirmOpen] = useState(false);
  const [confirmText, setConfirmText] = useState("");
  const [clearing, setClearing] = useState(false);
  const [clearError, setClearError] = useState<string | null>(null);
  const [clearedAt, setClearedAt] = useState<string | null>(null);

  async function exportCampaign() {
    setExporting(true);
    setExportError(null);
    try {
      const supabase = createClient();
      const data: Record<string, unknown> = {
        exported_at: new Date().toISOString(),
        schema_version: "0012",
      };

      for (const table of EXPORT_TABLES) {
        const { data: rows, error } = await supabase.from(table).select("*");
        if (error) throw new Error(`${table}: ${error.message}`);
        data[table] = rows ?? [];
      }
      for (const view of EXPORT_VIEWS) {
        const { data: rows, error } = await supabase.from(view).select("*");
        if (error) throw new Error(`${view}: ${error.message}`);
        data[view] = rows ?? [];
      }

      const stamp = new Date().toISOString().replace(/[:.]/g, "-");
      const blob = new Blob([JSON.stringify(data, null, 2)], {
        type: "application/json",
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `crusade-snapshot-${stamp}.json`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (err) {
      setExportError(describeError(err));
    } finally {
      setExporting(false);
    }
  }

  function openConfirm() {
    setConfirmText("");
    setClearError(null);
    setConfirmOpen(true);
  }

  function cancelConfirm() {
    if (clearing) return;
    setConfirmOpen(false);
    setConfirmText("");
    setClearError(null);
  }

  const confirmIsValid = CONFIRM_WORDS.includes(
    confirmText.trim().toUpperCase()
  );

  async function clearCampaign() {
    if (!confirmIsValid) return;
    setClearing(true);
    setClearError(null);
    try {
      const supabase = createClient();
      const { error } = await supabase.rpc("admin_clear_campaign");
      if (error) throw error;
      setConfirmOpen(false);
      setConfirmText("");
      setClearedAt(new Date().toISOString());
      router.refresh();
    } catch (err) {
      setClearError(describeError(err));
    } finally {
      setClearing(false);
    }
  }

  return (
    <div className="space-y-4">
      <div className="card p-6 space-y-4">
        <div>
          <div className="font-display text-parchment">
            Export Campaign Snapshot
          </div>
          <p className="text-sm text-parchment-dim font-body italic mt-1">
            Download a JSON file with every profile, deed, award, planet
            claim, ELO rating and leaderboard total. Run this before clearing
            so the season can be remembered in the histories.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <button
            onClick={exportCampaign}
            disabled={exporting}
            className="btn-primary disabled:opacity-50"
          >
            {exporting ? "Compiling archives…" : "Download Snapshot"}
          </button>
          {exportError && (
            <span className="text-sm text-blood">{exportError}</span>
          )}
        </div>
      </div>

      <div className="card p-6 space-y-4 border border-blood/40">
        <div>
          <div className="font-display text-parchment">
            Clear Campaign for New Season
          </div>
          <p className="text-sm text-parchment-dim font-body italic mt-1">
            Wipes all submissions, awards, planet claims, ELO ratings and the
            planet flip log. Profiles, factions, planets, the awards
            catalogue and game-system configuration are preserved.{" "}
            <span className="text-blood not-italic">This cannot be undone.</span>
          </p>
        </div>

        {!confirmOpen ? (
          <div className="flex flex-wrap items-center gap-3">
            <button onClick={openConfirm} className="btn-danger">
              Clear Campaign…
            </button>
            {clearedAt && (
              <span className="text-sm text-parchment-dim italic">
                Last cleared {new Date(clearedAt).toLocaleString()}.
              </span>
            )}
          </div>
        ) : (
          <div className="rounded border border-blood/60 bg-blood/5 p-4 space-y-3">
            <div className="text-sm text-parchment">
              To confirm, type{" "}
              <span className="font-mono text-blood">CLEAR</span> or{" "}
              <span className="font-mono text-blood">DELETE</span> below.
            </div>
            <input
              type="text"
              autoFocus
              value={confirmText}
              onChange={(e) => setConfirmText(e.target.value)}
              placeholder="Type CLEAR or DELETE"
              className="input w-full"
              disabled={clearing}
            />
            {clearError && (
              <div className="text-sm text-blood">{clearError}</div>
            )}
            <div className="flex justify-end gap-2">
              <button
                onClick={cancelConfirm}
                disabled={clearing}
                className="btn-ghost text-sm"
              >
                Cancel
              </button>
              <button
                onClick={clearCampaign}
                disabled={!confirmIsValid || clearing}
                className="btn-danger text-sm disabled:opacity-40 disabled:cursor-not-allowed"
              >
                {clearing ? "Wiping the slate…" : "Confirm Clear"}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
