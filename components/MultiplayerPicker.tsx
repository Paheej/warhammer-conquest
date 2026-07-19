'use client';

// =====================================================================
// components/MultiplayerPicker.tsx
// Roster builder for multiplayer battle reports. Two team lists — the
// submitter's side (allies) and the opposing side — each backed by the
// same searchable_players typeahead the AdversaryPicker uses. Only
// registered players can be listed: glory, ELO, and mirror records all
// require an account. Unregistered opponents belong in the description.
// =====================================================================

import { useEffect, useRef, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import type { BattleSide, SearchablePlayer } from '@/lib/types';

interface FactionOption { id: string; name: string; }

export interface ParticipantDraft {
  userId: string;
  displayName: string;
  avatarUrl: string | null;
  factionId: string | null;
  factionName: string | null;
  factionOptions: FactionOption[];
  side: BattleSide;
}

interface Props {
  value: ParticipantDraft[];
  onChange: (v: ParticipantDraft[]) => void;
  /** Exclude the current user from suggestions (they are the submitter). */
  currentUserId: string | null;
}

export default function MultiplayerPicker({ value, onChange, currentUserId }: Props) {
  const excludeIds = [currentUserId, ...value.map((p) => p.userId)].filter(Boolean) as string[];

  async function addPlayer(p: SearchablePlayer, side: BattleSide) {
    const supabase = createClient();
    const { data } = await supabase
      .from('player_factions')
      .select('faction_id, factions!inner(id, name)')
      .eq('user_id', p.id);

    const rows = (data ?? []) as unknown as Array<{ factions: FactionOption }>;
    let factions: FactionOption[] = rows.map((r) => ({ id: r.factions.id, name: r.factions.name }));

    if (factions.length === 0 && p.primary_faction_id && p.primary_faction_name) {
      factions = [{ id: p.primary_faction_id, name: p.primary_faction_name }];
    }

    const auto = factions.length === 1 ? factions[0] : null;
    onChange([
      ...value,
      {
        userId: p.id,
        displayName: p.display_name,
        avatarUrl: p.avatar_url,
        factionId: auto?.id ?? null,
        factionName: auto?.name ?? null,
        factionOptions: factions,
        side,
      },
    ]);
  }

  function removePlayer(userId: string) {
    onChange(value.filter((p) => p.userId !== userId));
  }

  function setFaction(userId: string, factionId: string) {
    onChange(
      value.map((p) => {
        if (p.userId !== userId) return p;
        const f = p.factionOptions.find((x) => x.id === factionId) ?? null;
        return { ...p, factionId: f?.id ?? null, factionName: f?.name ?? null };
      }),
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <TeamSection
        side="ally"
        label="Your side — teammates"
        hint="Commanders who fought alongside you. They share your result."
        participants={value.filter((p) => p.side === 'ally')}
        excludeIds={excludeIds}
        onAdd={(p) => addPlayer(p, 'ally')}
        onRemove={removePlayer}
        onFaction={setFaction}
      />
      <TeamSection
        side="opponent"
        label="Opposing side"
        hint="Commanders you fought against. They get the opposite result."
        participants={value.filter((p) => p.side === 'opponent')}
        excludeIds={excludeIds}
        onAdd={(p) => addPlayer(p, 'opponent')}
        onRemove={removePlayer}
        onFaction={setFaction}
      />
      <p className="text-xs italic text-parchment-dark">
        Only registered commanders can be listed — each earns full glory and ELO
        for their own result. Mention unregistered players in the description.
      </p>
    </div>
  );
}

function TeamSection({
  side, label, hint, participants, excludeIds, onAdd, onRemove, onFaction,
}: {
  side: BattleSide;
  label: string;
  hint: string;
  participants: ParticipantDraft[];
  excludeIds: string[];
  onAdd: (p: SearchablePlayer) => void;
  onRemove: (userId: string) => void;
  onFaction: (userId: string, factionId: string) => void;
}) {
  const [query, setQuery] = useState('');
  const [suggestions, setSuggestions] = useState<SearchablePlayer[]>([]);
  const [open, setOpen] = useState(false);
  const wrapRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onDown(e: MouseEvent) {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, []);

  useEffect(() => {
    if (query.trim().length < 2) {
      setSuggestions([]);
      return;
    }
    const t = setTimeout(async () => {
      const supabase = createClient();
      const { data } = await supabase
        .from('searchable_players')
        .select('id, display_name, avatar_url, primary_faction_id, primary_faction_name')
        .ilike('display_name', `%${query.trim()}%`)
        .limit(8);

      setSuggestions(
        ((data ?? []) as SearchablePlayer[]).filter((p) => !excludeIds.includes(p.id)),
      );
      setOpen(true);
    }, 250);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query]);

  const borderTone = side === 'ally' ? 'border-green-700/40' : 'border-red-700/40';

  return (
    <div ref={wrapRef} className={`relative rounded border ${borderTone} bg-ink/40 p-3`}>
      <div className="label">{label}</div>
      <p className="mt-0.5 text-xs text-parchment-dark">{hint}</p>

      {participants.length > 0 && (
        <ul className="mt-2 flex flex-col gap-2">
          {participants.map((p) => (
            <li key={p.userId} className="flex flex-wrap items-center gap-2 rounded border border-brass/20 bg-ink-2 px-2 py-1.5">
              <div className="h-7 w-7 shrink-0 overflow-hidden rounded-full border border-brass/40 bg-ink">
                {p.avatarUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={p.avatarUrl} alt="" className="h-full w-full object-cover" />
                ) : (
                  <div className="flex h-full w-full items-center justify-center text-xs text-brass-bright">
                    {p.displayName.charAt(0).toUpperCase()}
                  </div>
                )}
              </div>
              <span className="text-sm text-parchment">{p.displayName}</span>
              {p.factionOptions.length > 1 ? (
                <select
                  className="input ml-auto bg-ink py-1 text-xs text-parchment"
                  value={p.factionId ?? ''}
                  onChange={(e) => onFaction(p.userId, e.target.value)}
                >
                  <option value="" className="bg-ink text-parchment">— faction —</option>
                  {p.factionOptions.map((f) => (
                    <option key={f.id} value={f.id} className="bg-ink text-parchment">{f.name}</option>
                  ))}
                </select>
              ) : (
                <span className="ml-auto text-xs text-parchment-dark">
                  {p.factionName ?? 'No faction joined'}
                </span>
              )}
              <button
                type="button"
                onClick={() => onRemove(p.userId)}
                className="rounded border border-brass/40 px-1.5 py-0.5 text-xs text-parchment-dim hover:border-brass hover:text-brass-bright"
                aria-label={`Remove ${p.displayName}`}
              >
                ✕
              </button>
            </li>
          ))}
        </ul>
      )}

      <input
        type="text"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        onFocus={() => { if (suggestions.length > 0) setOpen(true); }}
        placeholder="Type a name to add a registered player…"
        className="input mt-2 w-full"
      />

      {open && suggestions.length > 0 && (
        <ul className="absolute left-3 right-3 top-full z-20 -mt-1 overflow-hidden rounded border border-brass/40 bg-ink-2 shadow-lg">
          {suggestions.map((s) => (
            <li key={s.id}>
              <button
                type="button"
                onClick={() => {
                  onAdd(s);
                  setQuery('');
                  setSuggestions([]);
                  setOpen(false);
                }}
                className="flex w-full items-center gap-2 px-3 py-2 text-left hover:bg-brass/10"
              >
                <div className="h-7 w-7 shrink-0 overflow-hidden rounded-full border border-brass/40 bg-ink">
                  {s.avatar_url ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={s.avatar_url} alt="" className="h-full w-full object-cover" />
                  ) : (
                    <div className="flex h-full w-full items-center justify-center text-xs text-brass-bright">
                      {s.display_name.charAt(0).toUpperCase()}
                    </div>
                  )}
                </div>
                <span className="text-sm text-parchment">{s.display_name}</span>
                {s.primary_faction_name && (
                  <span className="ml-auto text-xs text-parchment-dark">{s.primary_faction_name}</span>
                )}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
