"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type {
  Planet,
  Faction,
  GameSystem,
  GameSystemId,
  PlanetGameSystem,
} from "@/lib/types";

export function AdminPlanets({
  planets,
  factions,
  gameSystems,
  planetSystems,
}: {
  planets: Planet[];
  factions: Faction[];
  gameSystems: GameSystem[];
  planetSystems: PlanetGameSystem[];
}) {
  const router = useRouter();
  const [showNew, setShowNew] = useState(false);
  const [busy, setBusy] = useState(false);

  // New planet
  const [name, setName] = useState("");
  const [desc, setDesc] = useState("");
  const [threshold, setThreshold] = useState(100);
  const [x, setX] = useState(0.5);
  const [y, setY] = useState(0.5);

  const initialAllowed = useMemo(() => {
    const map = new Map<string, Set<GameSystemId>>();
    for (const row of planetSystems) {
      const set = map.get(row.planet_id) ?? new Set<GameSystemId>();
      set.add(row.game_system_id);
      map.set(row.planet_id, set);
    }
    return map;
  }, [planetSystems]);

  const [allowedByPlanet, setAllowedByPlanet] = useState<
    Map<string, Set<GameSystemId>>
  >(() => new Map(initialAllowed));
  const [savingSystemsFor, setSavingSystemsFor] = useState<string | null>(null);

  function getAllowed(planetId: string): Set<GameSystemId> {
    return allowedByPlanet.get(planetId) ?? initialAllowed.get(planetId) ?? new Set();
  }

  function isDirty(planetId: string): boolean {
    const current = allowedByPlanet.get(planetId);
    if (!current) return false;
    const original = initialAllowed.get(planetId) ?? new Set<GameSystemId>();
    if (current.size !== original.size) return true;
    for (const id of current) if (!original.has(id)) return true;
    return false;
  }

  function toggleSystem(planetId: string, systemId: GameSystemId) {
    setAllowedByPlanet((prev) => {
      const next = new Map(prev);
      const current = new Set(next.get(planetId) ?? initialAllowed.get(planetId) ?? []);
      if (current.has(systemId)) current.delete(systemId);
      else current.add(systemId);
      next.set(planetId, current);
      return next;
    });
  }

  async function saveSystems(planetId: string) {
    setSavingSystemsFor(planetId);
    const supabase = createClient();
    const allowed = getAllowed(planetId);

    const { error: dErr } = await supabase
      .from("planet_game_systems")
      .delete()
      .eq("planet_id", planetId);
    if (dErr) {
      setSavingSystemsFor(null);
      return alert(dErr.message);
    }

    if (allowed.size > 0) {
      const rows = Array.from(allowed).map((gsId) => ({
        planet_id: planetId,
        game_system_id: gsId,
      }));
      const { error: iErr } = await supabase
        .from("planet_game_systems")
        .insert(rows);
      if (iErr) {
        setSavingSystemsFor(null);
        return alert(iErr.message);
      }
    }

    setSavingSystemsFor(null);
    router.refresh();
  }

  async function createPlanet(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    const supabase = createClient();
    const { error } = await supabase.from("planets").insert({
      name,
      description: desc,
      threshold,
      position_x: x,
      position_y: y,
    });
    setBusy(false);
    if (error) return alert(error.message);
    setName(""); setDesc(""); setThreshold(100); setX(0.5); setY(0.5);
    setShowNew(false);
    router.refresh();
  }

  async function deletePlanet(id: string) {
    if (!confirm("Strike this world from the map? All progress toward it will be lost.")) return;
    const supabase = createClient();
    const { error } = await supabase.from("planets").delete().eq("id", id);
    if (error) return alert(error.message);
    router.refresh();
  }

  async function setController(planetId: string, factionId: string | null) {
    const supabase = createClient();
    const { error } = await supabase
      .from("planets")
      .update({
        controlling_faction_id: factionId,
        claimed_at: factionId ? new Date().toISOString() : null,
      })
      .eq("id", planetId);
    if (error) return alert(error.message);
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <button onClick={() => setShowNew((v) => !v)} className="btn-ghost">
          {showNew ? "Cancel" : "Add a New World"}
        </button>
      </div>

      {showNew && (
        <form onSubmit={createPlanet} className="card p-6 space-y-4">
          <div className="grid md:grid-cols-2 gap-4">
            <div>
              <label className="label">Name</label>
              <input
                type="text" required value={name}
                onChange={(e) => setName(e.target.value)}
                className="input w-full"
              />
            </div>
            <div>
              <label className="label">Threshold (points to claim)</label>
              <input
                type="number" min={1} required value={threshold}
                onChange={(e) => setThreshold(Number(e.target.value))}
                className="input w-full"
              />
            </div>
            <div>
              <label className="label">Map X (0 = left, 1 = right)</label>
              <input
                type="number" step="0.01" min={0} max={1} required value={x}
                onChange={(e) => setX(Number(e.target.value))}
                className="input w-full"
              />
            </div>
            <div>
              <label className="label">Map Y (0 = top, 1 = bottom)</label>
              <input
                type="number" step="0.01" min={0} max={1} required value={y}
                onChange={(e) => setY(Number(e.target.value))}
                className="input w-full"
              />
            </div>
          </div>
          <div>
            <label className="label">Description / Lore</label>
            <textarea
              value={desc} onChange={(e) => setDesc(e.target.value)}
              rows={3} className="input w-full"
            />
          </div>
          <div className="flex justify-end">
            <button type="submit" disabled={busy} className="btn-primary disabled:opacity-50">
              {busy ? "Inscribing…" : "Add World"}
            </button>
          </div>
        </form>
      )}

      <div className="space-y-3">
        {planets.map((p) => {
          const allowed = getAllowed(p.id);
          const dirty = isDirty(p.id);
          const saving = savingSystemsFor === p.id;
          return (
            <div key={p.id} className="card p-4 space-y-3">
              <div className="flex flex-wrap items-center gap-4">
                <div className="flex-1 min-w-[200px]">
                  <div className="font-display text-parchment">{p.name}</div>
                  <div className="text-xs text-parchment-dark">
                    threshold {p.threshold} · position ({p.position_x.toFixed(2)}, {p.position_y.toFixed(2)})
                  </div>
                </div>
                <select
                  value={p.controlling_faction_id ?? ""}
                  onChange={(e) => setController(p.id, e.target.value || null)}
                  className="input bg-ink text-parchment"
                >
                  <option value="" className="bg-ink text-parchment">— Contested —</option>
                  {factions.map((f) => (
                    <option key={f.id} value={f.id} className="bg-ink text-parchment">{f.name}</option>
                  ))}
                </select>
                <button onClick={() => deletePlanet(p.id)} className="btn-danger text-xs">
                  Delete
                </button>
              </div>

              <div className="border-t border-brass/20 pt-3">
                <div className="flex items-center justify-between gap-3 mb-2">
                  <div>
                    <div className="label !mb-0">Allowed game systems</div>
                    <div className="text-xs text-parchment-dark italic">
                      {allowed.size === 0
                        ? "No restrictions — every system allowed."
                        : `${allowed.size} system${allowed.size === 1 ? "" : "s"} allowed`}
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => saveSystems(p.id)}
                    disabled={!dirty || saving}
                    className="btn-ghost text-xs disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    {saving ? "Saving…" : "Save"}
                  </button>
                </div>
                <div className="flex flex-wrap gap-2">
                  {gameSystems.map((s) => {
                    const active = allowed.has(s.id);
                    return (
                      <button
                        key={s.id}
                        type="button"
                        onClick={() => toggleSystem(p.id, s.id)}
                        className={`rounded border px-3 py-1.5 text-sm transition-colors ${
                          active
                            ? "border-brass bg-brass/10 text-parchment"
                            : "border-brass/20 text-parchment-dim hover:border-brass/50"
                        }`}
                      >
                        {s.short_name || s.name}
                      </button>
                    );
                  })}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
