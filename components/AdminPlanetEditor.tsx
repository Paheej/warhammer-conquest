'use client';

// =====================================================================
// components/AdminPlanetEditor.tsx
// Admin-only inline editor for a single planet. Adds:
//   * Image URL field (external — admins paste a URL)
//   * Game system allowlist (checkboxes — empty = all allowed)
//
// Render this inside your existing /admin page for each planet row, or
// use it as the basis for a new planet-management panel.
// =====================================================================

import { useEffect, useMemo, useState } from 'react';
import { createBrowserClient } from '@/lib/supabase/client';
import type { GameSystem, GameSystemId } from '@/lib/types';

interface Planet {
  id: string;
  name: string;
  image_url?: string | null;
  position_x?: number | null;
  position_y?: number | null;
  claim_threshold?: number | null;
}

interface Props {
  planet: Planet;
  /** Optional: let the parent refresh its planet list after save. */
  onSaved?: () => void;
}

export default function AdminPlanetEditor({ planet, onSaved }: Props) {
  const supabase = useMemo(() => createBrowserClient(), []);

  const [imageUrl, setImageUrl] = useState(planet.image_url ?? '');
  const [systems, setSystems]   = useState<GameSystem[]>([]);
  const [allowed, setAllowed]   = useState<Set<GameSystemId>>(new Set());
  const [loading, setLoading]   = useState(true);
  const [saving, setSaving]     = useState(false);
  const [error, setError]       = useState<string | null>(null);
  const [saved, setSaved]       = useState(false);

  useEffect(() => {
    (async () => {
      setLoading(true);
      const [sysRes, pgsRes] = await Promise.all([
        supabase.from('game_systems').select('*').order('sort_order'),
        supabase.from('planet_game_systems').select('game_system_id').eq('planet_id', planet.id),
      ]);
      setSystems((sysRes.data ?? []) as GameSystem[]);
      setAllowed(new Set(((pgsRes.data ?? []) as Array<{ game_system_id: GameSystemId }>).map((r) => r.game_system_id)));
      setLoading(false);
    })();
  }, [planet.id, supabase]);

  function toggle(id: GameSystemId) {
    setAllowed((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
    setSaved(false);
  }

  async function save() {
    setSaving(true); setError(null); setSaved(false);

    // 1) Update image_url on the planet
    const { error: pErr } = await supabase
      .from('planets')
      .update({ image_url: imageUrl.trim() || null })
      .eq('id', planet.id);

    if (pErr) { setError(pErr.message); setSaving(false); return; }

    // 2) Reset allowlist rows for this planet, then insert current selection
    const { error: dErr } = await supabase
      .from('planet_game_systems')
      .delete()
      .eq('planet_id', planet.id);
    if (dErr) { setError(dErr.message); setSaving(false); return; }

    if (allowed.size > 0) {
      const rows = Array.from(allowed).map((gsId) => ({
        planet_id:      planet.id,
        game_system_id: gsId,
      }));
      const { error: iErr } = await supabase.from('planet_game_systems').insert(rows);
      if (iErr) { setError(iErr.message); setSaving(false); return; }
    }

    setSaving(false);
    setSaved(true);
    onSaved?.();
  }

  const allSelected = allowed.size === 0 || allowed.size === systems.length;

  return (
    <div className="flex flex-col gap-3 rounded border border-brass-700/40 bg-parchment-900/40 p-4">
      <div className="flex items-center gap-3">
        {imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={imageUrl}
            alt={planet.name}
            className="h-14 w-14 shrink-0 rounded-full border border-brass-700/50 object-cover"
            onError={(e) => { (e.currentTarget as HTMLImageElement).style.display = 'none'; }}
          />
        ) : (
          <div className="h-14 w-14 shrink-0 rounded-full border border-brass-700/50 bg-parchment-800" aria-hidden />
        )}
        <div>
          <div className="font-cinzel text-lg text-brass-100">{planet.name}</div>
          <div className="text-xs text-parchment-400">
            Threshold {planet.claim_threshold ?? '—'}
          </div>
        </div>
      </div>

      <label className="block">
        <span className="block text-sm font-medium text-parchment-200">Planet image URL</span>
        <input
          type="url"
          value={imageUrl}
          onChange={(e) => { setImageUrl(e.target.value); setSaved(false); }}
          placeholder="https://example.com/my-planet.jpg"
          className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100"
        />
        <p className="mt-1 text-xs text-parchment-400">
          External URL (e.g. imgur, your own CDN). Leave blank for the default circle.
        </p>
      </label>

      <fieldset>
        <legend className="text-sm font-medium text-parchment-200">Allowed game systems</legend>
        <p className="mt-1 text-xs text-parchment-400">
          Select which editions may be used for battles on this planet. Leave <strong>all unchecked</strong> to allow every system.
        </p>
        {loading ? (
          <div className="mt-2 text-xs text-parchment-400">Loading…</div>
        ) : (
          <div className="mt-2 grid grid-cols-1 gap-1 sm:grid-cols-2">
            {systems.map((s) => {
              const checked = allowed.has(s.id);
              return (
                <label key={s.id} className="flex items-center gap-2 rounded px-2 py-1 hover:bg-brass-700/10">
                  <input
                    type="checkbox"
                    checked={checked}
                    onChange={() => toggle(s.id)}
                    className="h-4 w-4 accent-brass-500"
                  />
                  <span className="text-sm text-parchment-100">{s.name}</span>
                </label>
              );
            })}
          </div>
        )}
        {allSelected && allowed.size === 0 && (
          <p className="mt-1 text-xs text-green-300/80">
            No restrictions — every game system allowed.
          </p>
        )}
      </fieldset>

      {error && (
        <div className="rounded border border-red-700/60 bg-red-900/30 px-3 py-2 text-sm text-red-200">
          {error}
        </div>
      )}
      {saved && !error && (
        <div className="rounded border border-green-700/60 bg-green-900/30 px-3 py-2 text-sm text-green-200">
          Saved.
        </div>
      )}

      <div>
        <button
          type="button"
          onClick={save}
          disabled={saving}
          className="rounded border border-brass-500 bg-brass-700/30 px-3 py-1.5 text-sm font-cinzel text-brass-100 hover:bg-brass-600/40 disabled:opacity-50"
        >
          {saving ? 'Saving…' : 'Save'}
        </button>
      </div>
    </div>
  );
}
