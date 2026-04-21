"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type { Faction, Profile } from "@/lib/types";

export function DashboardProfile({
  profile,
  factions,
}: {
  profile: Profile;
  factions: Faction[];
}) {
  const router = useRouter();
  const [displayName, setDisplayName] = useState(profile.display_name);
  const [factionId, setFactionId] = useState(profile.faction_id ?? "");
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setSaved(false);
    const supabase = createClient();
    const { error } = await supabase
      .from("profiles")
      .update({ display_name: displayName, faction_id: factionId || null })
      .eq("id", profile.id);
    setBusy(false);
    if (error) return alert(error.message);
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
    router.refresh();
  }

  return (
    <form onSubmit={save} className="card p-6">
      <div className="font-display uppercase tracking-widest text-xs text-brass mb-4">
        Your Banner
      </div>
      <div className="grid md:grid-cols-2 gap-4">
        <div>
          <label className="label">Commander's Name</label>
          <input
            type="text" required value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            className="input w-full"
          />
        </div>
        <div>
          <label className="label">Faction</label>
          <select
            value={factionId}
            onChange={(e) => setFactionId(e.target.value)}
            className="input w-full"
          >
            <option value="">— Unaligned —</option>
            {factions.map((f) => (
              <option key={f.id} value={f.id}>{f.name}</option>
            ))}
          </select>
        </div>
      </div>
      <div className="mt-4 flex items-center justify-end gap-3">
        {saved && <span className="text-sm text-brass-bright italic">Inscribed.</span>}
        <button type="submit" disabled={busy} className="btn-primary disabled:opacity-50">
          {busy ? "Saving…" : "Save"}
        </button>
      </div>
    </form>
  );
}
