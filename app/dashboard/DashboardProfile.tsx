"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { uploadImage } from "@/lib/upload-image";
import type { Profile } from "@/lib/types";

export function DashboardProfile({ profile }: { profile: Profile }) {
  const router = useRouter();
  const [displayName, setDisplayName] = useState(profile.display_name);
  const [avatarUrl, setAvatarUrl] = useState(profile.avatar_url ?? "");
  const [avatarFile, setAvatarFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const filePreview = useMemo(
    () => (avatarFile ? URL.createObjectURL(avatarFile) : null),
    [avatarFile],
  );
  useEffect(() => {
    return () => {
      if (filePreview) URL.revokeObjectURL(filePreview);
    };
  }, [filePreview]);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true); setSaved(false);
    const supabase = createClient();

    let nextAvatar: string | null = avatarUrl.trim() || null;
    if (avatarFile) {
      try {
        nextAvatar = await uploadImage(avatarFile);
      } catch (err) {
        setBusy(false);
        setError(err instanceof Error ? err.message : "Image upload failed.");
        return;
      }
    }

    const { error: dbError } = await supabase
      .from("profiles")
      .update({
        display_name: displayName,
        avatar_url: nextAvatar,
      })
      .eq("id", profile.id);
    setBusy(false);
    if (dbError) {
      setError(dbError.message);
      return;
    }
    if (avatarFile) {
      setAvatarUrl(nextAvatar ?? "");
      setAvatarFile(null);
    }
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
    router.refresh();
  }

  const trimmedAvatar = avatarUrl.trim();
  const previewSrc = filePreview ?? trimmedAvatar;

  return (
    <form onSubmit={save} className="card p-6">
      <div className="font-display uppercase tracking-widest text-xs text-brass mb-4">
        Player Information
      </div>
      <div className="flex items-start gap-4">
        <div className="h-20 w-20 shrink-0 overflow-hidden rounded-full border border-brass/50 bg-ink-2">
          {previewSrc ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={previewSrc}
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
            <label className="label">Upload an avatar</label>
            <input
              type="file"
              accept="image/*"
              onChange={(e) => setAvatarFile(e.target.files?.[0] ?? null)}
              className="input w-full file:bg-brass-dark file:text-parchment file:border-0 file:px-3 file:py-1 file:mr-3 file:font-display file:uppercase file:text-xs file:tracking-wider"
            />
            {avatarFile && (
              <p className="mt-1 text-xs text-parchment-dark italic">
                Uploading {avatarFile.name} on save.
              </p>
            )}
          </div>
          <div>
            <label className="label">Or paste an avatar URL</label>
            <input
              type="url"
              value={avatarUrl}
              onChange={(e) => setAvatarUrl(e.target.value)}
              placeholder="https://…"
              className="input w-full"
              disabled={!!avatarFile}
            />
            <p className="mt-1 text-xs text-parchment-dim italic">
              Discord sign-ins inherit your Discord avatar automatically. Upload a file or paste any image URL to override.
            </p>
          </div>
        </div>
      </div>
      {error && (
        <div className="mt-4 border border-blood bg-blood/20 px-3 py-2 text-sm text-parchment">
          {error}
        </div>
      )}
      <div className="mt-4 flex items-center justify-end gap-3">
        {saved && <span className="text-sm text-brass-bright italic">Inscribed.</span>}
        <button type="submit" disabled={busy} className="btn-primary disabled:opacity-50">
          {busy ? "Saving…" : "Save"}
        </button>
      </div>
    </form>
  );
}
