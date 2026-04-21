"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type { Planet, Faction } from "@/lib/types";

export function AdminPlanets({
  planets,
  factions,
}: {
  planets: Planet[];
  factions: Faction[];
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
          const controller = factions.find((f) => f.id === p.controlling_faction_id);
          return (
            <div key={p.id} className="card p-4 flex flex-wrap items-center gap-4">
              <div className="flex-1 min-w-[200px]">
                <div className="font-display text-parchment">{p.name}</div>
                <div className="text-xs text-parchment-dark">
                  threshold {p.threshold} · position ({p.position_x.toFixed(2)}, {p.position_y.toFixed(2)})
                </div>
              </div>
              <select
                value={p.controlling_faction_id ?? ""}
                onChange={(e) => setController(p.id, e.target.value || null)}
                className="input"
                style={controller ? { color: controller.color } : {}}
              >
                <option value="">— Contested —</option>
                {factions.map((f) => (
                  <option key={f.id} value={f.id}>{f.name}</option>
                ))}
              </select>
              <button onClick={() => deletePlanet(p.id)} className="btn-danger text-xs">
                Delete
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}
