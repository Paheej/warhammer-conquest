'use client';

// =====================================================================
// app/submit/SubmitPageClient.tsx
// Client wrapper: kind-picker tabs + per-kind forms. Battle uses the
// rich BattleSubmitForm. Painted/Lore use a simple shared form.
// =====================================================================

import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import BattleSubmitForm from '@/components/BattleSubmitForm';
import { POINT_PRESETS } from '@/lib/types';
import type { GameSystemId } from '@/lib/types';

interface Planet  { id: string; name: string; }
interface Faction { id: string; name: string; }

type Kind = 'battle' | 'painted' | 'lore';

interface Props {
  planets: Planet[];
  userFactions: Faction[];
  planetSystems: Array<{ planet_id: string; game_system_id: GameSystemId }>;
  currentUserId: string;
}

const KINDS: Array<{ id: Kind; label: string; icon: string; desc: string }> = [
  { id: 'battle',  label: 'Battle Report', icon: '⚔', desc: 'Log a game and claim glory on a world.' },
  { id: 'painted', label: 'Painted Model', icon: '🖌', desc: 'Share miniatures you finished painting.' },
  { id: 'lore',    label: 'Lore',          icon: '📜', desc: 'Write a piece of campaign fiction.' },
];

export default function SubmitPageClient({ planets, userFactions, planetSystems, currentUserId }: Props) {
  const [kind, setKind] = useState<Kind>('battle');

  return (
    <div>
      {/* Kind selector */}
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        {KINDS.map((k) => {
          const active = kind === k.id;
          return (
            <button
              key={k.id}
              type="button"
              onClick={() => setKind(k.id)}
              className={`rounded border px-3 py-3 text-left transition-colors ${
                active
                  ? 'border-brass-500 bg-brass-700/30 text-brass-100'
                  : 'border-brass-700/40 bg-parchment-950 text-parchment-200 hover:border-brass-600'
              }`}
            >
              <div className="flex items-center gap-2 font-cinzel text-base">
                <span aria-hidden>{k.icon}</span>
                {k.label}
              </div>
              <p className="mt-1 text-xs text-parchment-400">{k.desc}</p>
            </button>
          );
        })}
      </div>

      <div className="mt-6">
        {kind === 'battle' ? (
          <BattleSubmitForm
            planets={planets}
            userFactions={userFactions}
            planetSystems={planetSystems}
            currentUserId={currentUserId}
          />
        ) : (
          <SimpleSubmitForm
            kind={kind}
            planets={planets}
            userFactions={userFactions}
            currentUserId={currentUserId}
          />
        )}
      </div>
    </div>
  );
}

// -----------------------------------------------------------------
// Simple (painted / lore) form — no game system / adversary fields.
// -----------------------------------------------------------------
function SimpleSubmitForm({
  kind, planets, userFactions, currentUserId,
}: {
  kind: 'painted' | 'lore';
  planets: Planet[];
  userFactions: Faction[];
  currentUserId: string;
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [planetId, setPlanetId] = useState(planets[0]?.id ?? '');
  const [factionId, setFactionId] = useState(userFactions[0]?.id ?? '');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  // Use the canonical POINT_PRESETS from lib/types.ts so the initial value
  // matches one of the dropdown options (see #2).
  const [points, setPoints] = useState<number>(
    kind === 'painted' ? POINT_PRESETS.model[0].value : 2,
  );
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (!planetId || !factionId) {
      setError('Planet and faction are required.');
      return;
    }
    setSubmitting(true);
    // UI uses 'painted' / 'lore' / 'battle' for tab kinds; the DB
    // submission_type enum is ('game', 'model', 'lore', 'bonus'), so
    // map 'painted' -> 'model' before insert. (Battle submissions go
    // through BattleSubmitForm which maps 'battle' -> 'game'.)
    const dbType = kind === 'painted' ? 'model' : kind;
    const { error: err } = await supabase.from('submissions').insert({
      player_id:  currentUserId,
      type: dbType,
      status:     'pending',
      target_planet_id: planetId,
      faction_id: factionId,
      title:      title.trim() || (kind === 'painted' ? 'Painted model' : 'Lore entry'),
      body:       description.trim() || null,
      image_url:  imageUrl.trim() || null,
      points,
    });
    setSubmitting(false);
    if (err) { setError(err.message); return; }
    router.push('/dashboard?submitted=1');
    router.refresh();
  }

  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-4">
      <label className="block">
        <span className="label">Planet</span>
        <select
          value={planetId}
          onChange={(e) => setPlanetId(e.target.value)}
          className="input w-full bg-ink text-parchment"
        >
          {planets.map((p) => (
            <option key={p.id} value={p.id} className="bg-ink text-parchment">
              {p.name}
            </option>
          ))}
        </select>
      </label>

      <label className="block">
        <span className="label">Faction</span>
        <select
          value={factionId}
          onChange={(e) => setFactionId(e.target.value)}
          className="input w-full bg-ink text-parchment"
        >
          {userFactions.length === 0 ? (
            <option value="" className="bg-ink text-parchment">
              (Join a faction first)
            </option>
          ) : (
            userFactions.map((f) => (
              <option key={f.id} value={f.id} className="bg-ink text-parchment">
                {f.name}
              </option>
            ))
          )}
        </select>
      </label>

      <label className="block">
        <span className="label">Title</span>
        <input
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          className="input w-full"
          placeholder={kind === 'painted' ? 'Terminator Squad, 3rd Company' : 'The Dirge of Cadia'}
        />
      </label>

      <label className="block">
        <span className="label">
          {kind === 'painted' ? 'Notes (paint scheme, basing, etc.)' : 'The tale'}
        </span>
        <textarea
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          rows={kind === 'lore' ? 8 : 4}
          className="input w-full"
        />
      </label>

      <label className="block">
        <span className="label">
          Image URL {kind === 'painted' && <span className="text-parchment-dark normal-case">(recommended)</span>}
        </span>
        <input
          type="url"
          value={imageUrl}
          onChange={(e) => setImageUrl(e.target.value)}
          placeholder="https://…"
          className="input w-full"
        />
      </label>

      <label className="block">
        <span className="label">
          {kind === 'painted' ? 'Unit Size' : 'Claimed points'}
        </span>
        <select
          value={points}
          onChange={(e) => setPoints(Number(e.target.value))}
          className="input w-full bg-ink text-parchment"
        >
          {kind === 'painted'
            ? POINT_PRESETS.model.map((opt) => (
                <option
                  key={opt.value}
                  value={opt.value}
                  className="bg-ink text-parchment"
                >
                  {opt.label} · {opt.value} pts
                </option>
              ))
            : POINT_PRESETS.lore.map((opt) => (
                <option
                  key={opt.value}
                  value={opt.value}
                  className="bg-ink text-parchment"
                >
                  {opt.label} · {opt.value} pts
                </option>
              ))}
        </select>
        <p className="mt-1 text-xs italic text-parchment-dark">
          The Inquisition may adjust this value upon review.
        </p>
      </label>

      {error && (
        <div className="border border-blood bg-blood/20 px-3 py-2 text-sm text-parchment">
          {error}
        </div>
      )}

      <button
        type="submit"
        disabled={submitting || userFactions.length === 0}
        className="btn-primary disabled:opacity-50"
      >
        {submitting ? 'Submitting…' : 'Submit for Approval'}
      </button>
    </form>
  );
}
