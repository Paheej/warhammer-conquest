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

  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState("");
  const [editColor, setEditColor] = useState("#b8892d");
  const [savingEdit, setSavingEdit] = useState(false);

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

  function startEdit(f: Faction) {
    setEditingId(f.id);
    setEditName(f.name);
    setEditColor(f.color);
  }

  function cancelEdit() {
    setEditingId(null);
  }

  async function saveEdit(id: string) {
    setSavingEdit(true);
    const supabase = createClient();
    const { error } = await supabase
      .from("factions")
      .update({ name: editName, color: editColor })
      .eq("id", id);
    setSavingEdit(false);
    if (error) return alert(error.message);
    setEditingId(null);
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
        {factions.map((f) => {
          const isEditing = editingId === f.id;
          return (
            <div key={f.id} className="card p-3">
              {isEditing ? (
                <div className="space-y-3">
                  <div className="flex items-center gap-3">
                    <input
                      type="color"
                      value={editColor}
                      onChange={(e) => setEditColor(e.target.value)}
                      className="input w-12 h-10 p-1 shrink-0"
                      aria-label="Banner color"
                    />
                    <input
                      type="text"
                      value={editName}
                      onChange={(e) => setEditName(e.target.value)}
                      className="input flex-1"
                      placeholder="Faction name"
                    />
                  </div>
                  <div className="flex justify-end gap-2">
                    <button
                      onClick={cancelEdit}
                      disabled={savingEdit}
                      className="btn-ghost text-xs"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={() => saveEdit(f.id)}
                      disabled={savingEdit || !editName.trim()}
                      className="btn-primary text-xs disabled:opacity-50"
                    >
                      {savingEdit ? "Saving…" : "Save"}
                    </button>
                  </div>
                </div>
              ) : (
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-sm shrink-0" style={{ backgroundColor: f.color }} />
                  <div className="flex-1 font-display text-parchment">{f.name}</div>
                  <button
                    onClick={() => startEdit(f)}
                    className="btn-ghost text-xs"
                  >
                    Edit
                  </button>
                  <button
                    onClick={() => deleteFaction(f.id)}
                    className="btn-danger text-xs"
                  >
                    Delete
                  </button>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
