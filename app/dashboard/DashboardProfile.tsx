"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type { Profile } from "@/lib/types";

export function DashboardProfile({ profile }: { profile: Profile }) {
  const router = useRouter();
  const [displayName, setDisplayName] = useState(profile.display_name);
  const [avatarUrl, setAvatarUrl] = useState(profile.avatar_url ?? "");
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setSaved(false);
    const supabase = createClient();
    const trimmed = avatarUrl.trim();
    const { error } = await supabase
      .from("profiles")
      .update({
        display_name: displayName,
        avatar_url: trimmed || null,
      })
      .eq("id", profile.id);
    setBusy(false);
    if (error) return alert(error.message);
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
    router.refresh();
  }

  const trimmedAvatar = avatarUrl.trim();

  return (
    <form onSubmit={save} className="card p-6">
      <div className="font-display uppercase tracking-widest text-xs text-brass mb-4">
        Player Information
      </div>
      <div className="flex items-start gap-4">
        <div className="h-20 w-20 shrink-0 overflow-hidden rounded-full border border-brass/50 bg-ink-2">
          {trimmedAvatar ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={trimmedAvatar}
              alt={displayName || "Avatar"}
              className="h-full w-full object-cover"
            />
          ) : (
            <div className="flex h-full w-full items-center justify-center font-display text-2xl text-brass">
              {(displayName || "?").charAt(0).toUpperCase()}
            </div>
          )}
        </div>
        <div className="flex-1 space-y-4">
          <div>
            <label className="label">Commander&apos;s Name</label>
            <input
              type="text" required value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              className="input w-full"
            />
          </div>
          <div>
            <label className="label">Avatar URL</label>
            <input
              type="url"
              value={avatarUrl}
              onChange={(e) => setAvatarUrl(e.target.value)}
              placeholder="https://…"
              className="input w-full"
            />
            <p className="mt-1 text-xs text-parchment-dim italic">
              Discord sign-ins inherit your Discord avatar automatically. Paste any image URL to override.
            </p>
          </div>
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
