'use client';

// =====================================================================
// app/submit/SubmitPageClient.tsx
// Client wrapper: kind-picker tabs + per-kind forms. Battle uses the
// rich BattleSubmitForm. Painted/Lore use a simple shared form.
// =====================================================================

import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createBrowserClient } from '@/lib/supabase/client';
import BattleSubmitForm from '@/components/BattleSubmitForm';
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
  const supabase = useMemo(() => createBrowserClient(), []);

  const [planetId, setPlanetId] = useState(planets[0]?.id ?? '');
  const [factionId, setFactionId] = useState(userFactions[0]?.id ?? '');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [points, setPoints] = useState(kind === 'painted' ? 3 : 2);
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
    const { error: err } = await supabase.from('submissions').insert({
      user_id:    currentUserId,
      kind,
      status:     'pending',
      planet_id:  planetId,
      faction_id: factionId,
      title:      title.trim() || (kind === 'painted' ? 'Painted model' : 'Lore entry'),
      description: description.trim() || null,
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
        <span className="block text-sm font-medium text-parchment-200">Planet</span>
        <select
          value={planetId}
          onChange={(e) => setPlanetId(e.target.value)}
          className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100"
        >
          {planets.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select>
      </label>

      <label className="block">
        <span className="block text-sm font-medium text-parchment-200">Faction</span>
        <select
          value={factionId}
          onChange={(e) => setFactionId(e.target.value)}
          className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100"
        >
          {userFactions.length === 0
            ? <option value="">(Join a faction first)</option>
            : userFactions.map((f) => <option key={f.id} value={f.id}>{f.name}</option>)}
        </select>
      </label>

      <label className="block">
        <span className="block text-sm font-medium text-parchment-200">Title</span>
        <input
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100"
          placeholder={kind === 'painted' ? 'Primaris Captain, finished' : 'The Dirge of Cadia'}
        />
      </label>

      <label className="block">
        <span className="block text-sm font-medium text-parchment-200">
          {kind === 'painted' ? 'Notes (paint scheme, basing, etc.)' : 'The tale'}
        </span>
        <textarea
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          rows={kind === 'lore' ? 8 : 4}
          className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100"
        />
      </label>

      <label className="block">
        <span className="block text-sm font-medium text-parchment-200">
          Image URL {kind === 'painted' && <span className="text-parchment-400">(recommended)</span>}
        </span>
        <input
          type="url"
          value={imageUrl}
          onChange={(e) => setImageUrl(e.target.value)}
          placeholder="https://…"
          className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100"
        />
      </label>

      <label className="block">
        <span className="block text-sm font-medium text-parchment-200">Claimed points</span>
        <select
          value={points}
          onChange={(e) => setPoints(Number(e.target.value))}
          className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100"
        >
          {[1,2,3,4,5,7,10].map((n) => <option key={n} value={n}>{n}</option>)}
        </select>
        <p className="mt-1 text-xs text-parchment-400">
          Admins may adjust the final value before approving.
        </p>
      </label>

      {error && (
        <div className="rounded border border-red-700/60 bg-red-900/30 px-3 py-2 text-sm text-red-200">
          {error}
        </div>
      )}

      <button
        type="submit"
        disabled={submitting || userFactions.length === 0}
        className="rounded border border-brass-500 bg-brass-700/40 px-4 py-2.5 font-cinzel text-brass-100 hover:bg-brass-600/40 disabled:opacity-50"
      >
        {submitting ? 'Submitting…' : 'Submit for Approval'}
      </button>
    </form>
  );
}
