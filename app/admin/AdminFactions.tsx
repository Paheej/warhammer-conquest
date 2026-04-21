"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type { Faction } from "@/lib/types";

export function AdminFactions({ factions }: { factions: Faction[] }) {
  const router = useRouter();
  const [showNew, setShowNew] = useState(false);
  const [name, setName] = useState("");
  const [color, setColor] = useState("#b8892d");
  const [busy, setBusy] = useState(false);

  async function createFaction(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    const supabase = createClient();
    const { error } = await supabase.from("factions").insert({ name, color });
    setBusy(false);
    if (error) return alert(error.message);
    setName(""); setColor("#b8892d");
    setShowNew(false);
    router.refresh();
  }

  async function deleteFaction(id: string) {
    if (!confirm("Banish this faction from the campaign? Their submissions will remain but unassociated.")) return;
    const supabase = createClient();
    const { error } = await supabase.from("factions").delete().eq("id", id);
    if (error) return alert(error.message);
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <button onClick={() => setShowNew((v) => !v)} className="btn-ghost">
          {showNew ? "Cancel" : "Add a New Faction"}
        </button>
      </div>

      {showNew && (
        <form onSubmit={createFaction} className="card p-6 space-y-4">
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
              <label className="label">Banner Color</label>
              <input
                type="color" value={color}
                onChange={(e) => setColor(e.target.value)}
                className="input w-full h-11 p-1"
              />
            </div>
          </div>
          <div className="flex justify-end">
            <button type="submit" disabled={busy} className="btn-primary disabled:opacity-50">
              {busy ? "Inscribing…" : "Add Faction"}
            </button>
          </div>
        </form>
      )}

      <div className="grid md:grid-cols-2 gap-3">
        {factions.map((f) => (
          <div key={f.id} className="card p-3 flex items-center gap-3">
            <div className="w-8 h-8 rounded-sm" style={{ backgroundColor: f.color }} />
            <div className="flex-1 font-display text-parchment">{f.name}</div>
            <button
              onClick={() => deleteFaction(f.id)}
              className="btn-danger text-xs"
            >
              Delete
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
