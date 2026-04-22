'use client';

// =====================================================================
// components/AdversaryPicker.tsx
// Typeahead search over profiles. Emits {user_id, display_name,
// faction_id, faction_name} when a player is picked, or a free-text
// adversary name when nothing is selected.
// =====================================================================

import { useEffect, useRef, useState } from 'react';
import { createBrowserClient } from '@/lib/supabase/client';
import type { SearchablePlayer, PlayerFaction } from '@/lib/types';

export interface AdversaryValue {
  /** Free-text name (always set while typing). */
  name: string;
  /** Linked user if one has been selected from the dropdown. */
  userId: string | null;
  /** Faction the adversary was playing — required when linked. */
  factionId: string | null;
  factionName: string | null;
}

interface Props {
  value: AdversaryValue;
  onChange: (v: AdversaryValue) => void;
  /** Exclude the current user from suggestions. */
  currentUserId: string | null;
}

interface Faction { id: string; name: string; }

export default function AdversaryPicker({ value, onChange, currentUserId }: Props) {
  const [query, setQuery] = useState(value.name);
  const [suggestions, setSuggestions] = useState<SearchablePlayer[]>([]);
  const [opponentFactions, setOpponentFactions] = useState<Faction[]>([]);
  const [loadingSuggest, setLoadingSuggest] = useState(false);
  const [open, setOpen] = useState(false);
  const wrapRef = useRef<HTMLDivElement>(null);

  // Close suggestions on outside click
  useEffect(() => {
    function onDown(e: MouseEvent) {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, []);

  // Debounced search for suggestions
  useEffect(() => {
    // Keep free-text name in sync with typing
    onChange({ ...value, name: query, userId: value.userId, factionId: value.factionId, factionName: value.factionName });

    // If a user is already linked, don't re-search unless they edit away from it
    if (value.userId) return;

    if (query.trim().length < 2) {
      setSuggestions([]);
      return;
    }

    const t = setTimeout(async () => {
      setLoadingSuggest(true);
      const supabase = createBrowserClient();
      const { data } = await supabase
        .from('searchable_players')
        .select('id, display_name, avatar_url, primary_faction_id, primary_faction_name')
        .ilike('display_name', `%${query.trim()}%`)
        .limit(8);

      setSuggestions(
        ((data ?? []) as SearchablePlayer[]).filter((p) => p.id !== currentUserId)
      );
      setLoadingSuggest(false);
      setOpen(true);
    }, 250);

    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query]);

  // When a user is linked, fetch ALL factions they've played so the
  // submitter can pick which one the opponent fielded this battle.
  useEffect(() => {
    if (!value.userId) { setOpponentFactions([]); return; }
    (async () => {
      const supabase = createBrowserClient();
      const { data } = await supabase
        .from('player_factions')
        .select('faction_id, factions!inner(id, name)')
        .eq('user_id', value.userId);

      const rows = (data ?? []) as unknown as Array<{ factions: { id: string; name: string } }>;
      let factions: Faction[] = rows.map((r) => ({ id: r.factions.id, name: r.factions.name }));

      // Fallback: include primary faction from profile if missing
      if (factions.length === 0) {
        const { data: prof } = await supabase
          .from('profiles')
          .select('faction_id, factions(id, name)')
          .eq('id', value.userId)
          .maybeSingle();
        const pf = (prof as unknown as { factions: { id: string; name: string } | null } | null)?.factions;
        if (pf) factions = [pf];
      }

      setOpponentFactions(factions);

      // Auto-select if only one faction available
      if (factions.length === 1 && !value.factionId) {
        onChange({ ...value, factionId: factions[0].id, factionName: factions[0].name });
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value.userId]);

  function pick(p: SearchablePlayer) {
    onChange({
      name: p.display_name,
      userId: p.id,
      factionId: p.primary_faction_id,
      factionName: p.primary_faction_name,
    });
    setQuery(p.display_name);
    setOpen(false);
  }

  function clearLink() {
    onChange({ name: query, userId: null, factionId: null, factionName: null });
  }

  return (
    <div ref={wrapRef} className="relative flex flex-col gap-2">
      <label className="block">
        <span className="block text-sm font-medium text-parchment-200">Adversary</span>
        <div className="mt-1 flex items-stretch gap-2">
          <input
            type="text"
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              if (value.userId) {
                // User edited -> break the link
                clearLink();
              }
            }}
            onFocus={() => { if (suggestions.length > 0) setOpen(true); }}
            placeholder="Type a name — registered players will auto-suggest"
            className="flex-1 rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100 placeholder:text-parchment-500 focus:border-brass-500 focus:outline-none"
          />
          {value.userId && (
            <button
              type="button"
              onClick={clearLink}
              className="rounded border border-brass-700/40 px-2 py-1 text-xs text-parchment-300 hover:text-brass-200"
              aria-label="Unlink opponent"
            >
              Unlink
            </button>
          )}
        </div>
      </label>

      {open && suggestions.length > 0 && (
        <ul className="absolute top-full z-20 mt-1 w-full overflow-hidden rounded border border-brass-700/40 bg-parchment-900 shadow-lg">
          {loadingSuggest && (
            <li className="px-3 py-2 text-sm text-parchment-400">Searching…</li>
          )}
          {suggestions.map((s) => (
            <li key={s.id}>
              <button
                type="button"
                onClick={() => pick(s)}
                className="flex w-full items-center gap-2 px-3 py-2 text-left hover:bg-brass-700/20"
              >
                <div className="h-7 w-7 shrink-0 overflow-hidden rounded-full border border-brass-700/40 bg-parchment-800">
                  {s.avatar_url ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={s.avatar_url} alt="" className="h-full w-full object-cover" />
                  ) : (
                    <div className="flex h-full w-full items-center justify-center text-xs text-brass-300">
                      {s.display_name.charAt(0).toUpperCase()}
                    </div>
                  )}
                </div>
                <span className="text-sm text-parchment-100">{s.display_name}</span>
                {s.primary_faction_name && (
                  <span className="ml-auto text-xs text-parchment-400">{s.primary_faction_name}</span>
                )}
              </button>
            </li>
          ))}
        </ul>
      )}

      {value.userId && (
        <div className="rounded border border-green-700/40 bg-green-900/20 px-3 py-2 text-xs text-green-200">
          <div className="flex flex-wrap items-center gap-2">
            <span>✓ Linked to <strong>{value.name}</strong></span>
            <span className="text-green-300/70">— they&apos;ll earn glory + ELO from this match.</span>
          </div>

          {opponentFactions.length > 1 ? (
            <label className="mt-2 block">
              <span className="block text-xs text-green-200">Which faction were they fielding?</span>
              <select
                className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-2 py-1 text-parchment-100"
                value={value.factionId ?? ''}
                onChange={(e) => {
                  const f = opponentFactions.find((x) => x.id === e.target.value);
                  onChange({ ...value, factionId: f?.id ?? null, factionName: f?.name ?? null });
                }}
              >
                <option value="">— select faction —</option>
                {opponentFactions.map((f) => (
                  <option key={f.id} value={f.id}>{f.name}</option>
                ))}
              </select>
            </label>
          ) : value.factionName ? (
            <div className="mt-1 text-green-300/80">Playing as: {value.factionName}</div>
          ) : null}
        </div>
      )}
    </div>
  );
}
