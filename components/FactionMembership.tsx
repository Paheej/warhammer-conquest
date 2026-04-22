'use client';

// =====================================================================
// components/FactionMembership.tsx
// Lets a player join/leave multiple factions, and choose their primary.
// Drop this into app/dashboard/page.tsx so users can manage memberships.
// =====================================================================

import { useEffect, useMemo, useState } from 'react';
import { createBrowserClient } from '@/lib/supabase/client';

interface Faction { id: string; name: string; color?: string | null; }

interface Props {
  userId: string;
}

export default function FactionMembership({ userId }: Props) {
  const supabase = useMemo(() => createBrowserClient(), []);

  const [allFactions, setAllFactions]   = useState<Faction[]>([]);
  const [memberships, setMemberships]   = useState<Array<{ faction_id: string; is_primary: boolean }>>([]);
  const [loading, setLoading]           = useState(true);
  const [busy, setBusy]                 = useState<string | null>(null);
  const [error, setError]               = useState<string | null>(null);

  async function refresh() {
    setLoading(true);
    const [all, mine] = await Promise.all([
      supabase.from('factions').select('id, name, color').order('name'),
      supabase.from('player_factions').select('faction_id, is_primary').eq('user_id', userId),
    ]);
    setAllFactions((all.data ?? []) as Faction[]);
    setMemberships((mine.data ?? []) as Array<{ faction_id: string; is_primary: boolean }>);
    setLoading(false);
  }

  useEffect(() => { void refresh(); /* eslint-disable-next-line */ }, [userId]);

  const joinedIds    = new Set(memberships.map((m) => m.faction_id));
  const primaryId    = memberships.find((m) => m.is_primary)?.faction_id ?? null;
  const availableToJoin = allFactions.filter((f) => !joinedIds.has(f.id));

  async function join(fid: string) {
    setBusy(fid); setError(null);
    const isFirst = memberships.length === 0;
    const { error } = await supabase
      .from('player_factions')
      .insert({ user_id: userId, faction_id: fid, is_primary: isFirst });
    if (error) setError(error.message);
    // If this is the player's first faction, also set it as profile.faction_id
    // so legacy code still works.
    if (!error && isFirst) {
      await supabase.from('profiles').update({ faction_id: fid }).eq('id', userId);
    }
    await refresh();
    setBusy(null);
  }

  async function leave(fid: string) {
    if (memberships.length === 1) {
      setError('You must belong to at least one faction.');
      return;
    }
    setBusy(fid); setError(null);
    const wasPrimary = primaryId === fid;
    const { error } = await supabase
      .from('player_factions')
      .delete()
      .eq('user_id', userId)
      .eq('faction_id', fid);
    if (error) {
      setError(error.message);
      setBusy(null);
      return;
    }
    if (wasPrimary) {
      const remaining = memberships.filter((m) => m.faction_id !== fid);
      if (remaining[0]) {
        await supabase
          .from('player_factions')
          .update({ is_primary: true })
          .eq('user_id', userId)
          .eq('faction_id', remaining[0].faction_id);
        await supabase.from('profiles').update({ faction_id: remaining[0].faction_id }).eq('id', userId);
      }
    }
    await refresh();
    setBusy(null);
  }

  async function makePrimary(fid: string) {
    setBusy(fid); setError(null);
    // Clear all primaries, then set one.
    await supabase.from('player_factions').update({ is_primary: false }).eq('user_id', userId);
    const { error } = await supabase
      .from('player_factions')
      .update({ is_primary: true })
      .eq('user_id', userId)
      .eq('faction_id', fid);
    if (error) { setError(error.message); setBusy(null); return; }
    await supabase.from('profiles').update({ faction_id: fid }).eq('id', userId);
    await refresh();
    setBusy(null);
  }

  if (loading) return <div className="text-sm text-parchment-400">Loading faction memberships…</div>;

  const joined = memberships
    .map((m) => ({ ...m, faction: allFactions.find((f) => f.id === m.faction_id) }))
    .filter((row) => row.faction);

  return (
    <section className="rounded border border-brass-700/40 bg-parchment-900/40 p-4">
      <h2 className="font-cinzel text-lg text-brass-100">Faction Memberships</h2>
      <p className="mt-1 text-sm text-parchment-300">
        You may pledge your banner to multiple factions. One is marked <em>primary</em> — it&apos;s the default
        when submitting deeds, and is used for leaderboard display.
      </p>

      {error && (
        <div className="mt-3 rounded border border-red-700/60 bg-red-900/30 px-3 py-2 text-sm text-red-200">
          {error}
        </div>
      )}

      <ul className="mt-4 flex flex-col gap-2">
        {joined.map((row) => (
          <li
            key={row.faction_id}
            className="flex flex-wrap items-center gap-2 rounded border border-brass-700/40 bg-parchment-950 px-3 py-2"
          >
            <span
              className="inline-block h-3 w-3 rounded-full"
              style={{ backgroundColor: row.faction?.color ?? '#7a5b20' }}
              aria-hidden
            />
            <span className="font-cinzel text-parchment-100">{row.faction?.name}</span>
            {row.is_primary && (
              <span className="rounded border border-brass-600 bg-brass-700/30 px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-brass-100">
                Primary
              </span>
            )}
            <div className="ml-auto flex gap-2">
              {!row.is_primary && (
                <button
                  type="button"
                  onClick={() => makePrimary(row.faction_id)}
                  disabled={busy === row.faction_id}
                  className="rounded border border-brass-700/40 px-2 py-1 text-xs text-parchment-200 hover:text-brass-100 disabled:opacity-50"
                >
                  Make primary
                </button>
              )}
              <button
                type="button"
                onClick={() => leave(row.faction_id)}
                disabled={busy === row.faction_id || memberships.length === 1}
                className="rounded border border-red-800/50 px-2 py-1 text-xs text-red-300 hover:bg-red-900/30 disabled:opacity-40"
              >
                Leave
              </button>
            </div>
          </li>
        ))}
      </ul>

      {availableToJoin.length > 0 && (
        <div className="mt-4">
          <label className="block text-sm text-parchment-200">Pledge to another faction</label>
          <div className="mt-1 flex flex-wrap gap-2">
            {availableToJoin.map((f) => (
              <button
                key={f.id}
                type="button"
                onClick={() => join(f.id)}
                disabled={busy === f.id}
                className="rounded border border-brass-700/40 bg-parchment-950 px-3 py-1.5 text-sm text-parchment-100 hover:border-brass-500 disabled:opacity-50"
              >
                + {f.name}
              </button>
            ))}
          </div>
        </div>
      )}
    </section>
  );
}
