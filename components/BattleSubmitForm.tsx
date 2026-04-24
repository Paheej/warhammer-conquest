'use client';

// =====================================================================
// components/BattleSubmitForm.tsx
// Dynamic battle-report form. Drives game size + point value off the
// `game_systems` + `point_schemes` + `video_game_titles` tables.
//
// Use this inside app/submit/page.tsx when the user picks "Battle".
// =====================================================================

import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import AdversaryPicker, { type AdversaryValue } from './AdversaryPicker';
import type {
  GameSystem, GameSystemId, GameSize, BattleResult,
  PointScheme, VideoGameTitle,
} from '@/lib/types';

interface Planet   { id: string; name: string; }
interface Faction  { id: string; name: string; }

interface Props {
  planets: Planet[];
  /** Factions the current user has joined (many-to-many). At least one required. */
  userFactions: Faction[];
  /** Per-planet allowlist rows. If a planet has none, all systems allowed. */
  planetSystems: Array<{ planet_id: string; game_system_id: GameSystemId }>;
  currentUserId: string;
}

export default function BattleSubmitForm({ planets, userFactions, planetSystems, currentUserId }: Props) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  // Reference data loaded from supabase
  const [systems,    setSystems]    = useState<GameSystem[]>([]);
  const [schemes,    setSchemes]    = useState<PointScheme[]>([]);
  const [videoGames, setVideoGames] = useState<VideoGameTitle[]>([]);

  // Form state
  const [planetId, setPlanetId]   = useState<string>(planets[0]?.id ?? '');
  const [factionId, setFactionId] = useState<string>(userFactions[0]?.id ?? '');
  const [systemId, setSystemId]   = useState<GameSystemId | ''>('');
  const [size, setSize]           = useState<GameSize>('standard');
  const [result, setResult]       = useState<BattleResult>('win');
  const [videoGameId, setVideoGameId] = useState<number | ''>('');
  const [title, setTitle]         = useState('');
  const [description, setDescription] = useState('');
  const [imageUrl, setImageUrl]   = useState('');
  const [adversary, setAdversary] = useState<AdversaryValue>({
    name: '', userId: null, factionId: null, factionName: null,
  });

  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Load systems + schemes + video games
  useEffect(() => {
    (async () => {
      const [sysRes, schRes, vgRes] = await Promise.all([
        supabase.from('game_systems').select('*').order('sort_order'),
        supabase.from('point_schemes').select('*'),
        supabase.from('video_game_titles').select('*').order('sort_order'),
      ]);
      const sys = (sysRes.data ?? []) as GameSystem[];
      setSystems(sys);
      setSchemes((schRes.data ?? []) as PointScheme[]);
      setVideoGames((vgRes.data ?? []) as VideoGameTitle[]);

      // Default selection: the is_default row, else first allowed system on default planet.
      const allowed = allowedForPlanet(planets[0]?.id ?? '', planetSystems, sys);
      const def = sys.find((s) => s.is_default && allowed.some((a) => a.id === s.id))
               ?? allowed[0]
               ?? sys[0];
      if (def) setSystemId(def.id);
    })();
  }, [supabase, planets, planetSystems]);

  // Systems allowed for the currently-selected planet
  const allowedSystems = useMemo(
    () => allowedForPlanet(planetId, planetSystems, systems),
    [planetId, planetSystems, systems],
  );

  // If the currently-selected system isn't allowed on a newly-selected planet,
  // snap to default / first allowed.
  useEffect(() => {
    if (allowedSystems.length === 0) return;
    if (!systemId || !allowedSystems.some((s) => s.id === systemId)) {
      const def = allowedSystems.find((s) => s.is_default) ?? allowedSystems[0];
      setSystemId(def.id);
    }
  }, [allowedSystems, systemId]);

  const currentSystem = systems.find((s) => s.id === systemId);

  // When system changes, reset size appropriately
  useEffect(() => {
    if (!currentSystem) return;
    if (currentSystem.supports_size) {
      if (size === 'n/a') setSize('standard');
    } else {
      setSize('n/a');
    }
    // Reset video game selection if no longer applicable
    if (!currentSystem.supports_video_game) setVideoGameId('');
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [systemId]);

  // Computed point value from the scheme table
  const points = useMemo(() => {
    const match = schemes.find(
      (s) => s.game_system_id === systemId && s.game_size === size && s.result === result,
    );
    return match?.points ?? 0;
  }, [schemes, systemId, size, result]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (!planetId) { setError('Pick a planet.'); return; }
    if (!factionId) { setError('Pick which of your factions fought this battle.'); return; }
    if (!systemId) { setError('Pick a game system.'); return; }
    if (currentSystem?.supports_video_game && !videoGameId) {
      setError('Pick which video game this was played in.');
      return;
    }
    if (adversary.userId && !adversary.factionId) {
      setError('Pick which faction the linked opponent fielded.');
      return;
    }
    if (!adversary.name.trim()) {
      setError('Enter an adversary (name or link).');
      return;
    }

    setSubmitting(true);

    const payload: Record<string, unknown> = {
      player_id:    currentUserId,
      // UI kind is 'battle'; DB submission_type enum uses 'game'.
      type:       'game',
      status:     'pending',
      title:      title.trim() || `${result.toUpperCase()} vs ${adversary.name.trim()}`,
      body:       description.trim() || null,
      image_url:  imageUrl.trim() || null,
      target_planet_id: planetId,
      faction_id: factionId,
      points,
      game_system_id:      systemId,
      game_size:           size,
      result,
      opponent_name:       adversary.name.trim() || null,
      video_game_title_id: videoGameId === '' ? null : videoGameId,
      adversary_user_id:   adversary.userId,
      adversary_faction_id: adversary.factionId,
    };

    // If no linked adversary, stash the opponent name in the title/description
    if (!adversary.userId && !title.trim()) {
      payload.title = `${result.toUpperCase()} vs ${adversary.name.trim()}`;
    }

    const { error: err } = await supabase.from('submissions').insert(payload);

    setSubmitting(false);

    if (err) {
      setError(err.message);
      return;
    }

    router.push('/dashboard?submitted=1');
    router.refresh();
  }

  // Sizes available for the current system
  const sizeOptions: GameSize[] = currentSystem?.supports_size
    ? ['small', 'standard', 'large']
    : ['n/a'];

  const sizeLabel: Record<GameSize, string> = {
    small:    'Small — Combat Patrol / Boarding Action',
    standard: 'Standard — Incursion',
    large:    'Large — Strike Force / Apocalypse',
    'n/a':    'Standard (fixed)',
  };

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-4">
      {/* Planet */}
      <label className="block">
        <span className="block text-sm font-medium text-parchment-200">Planet</span>
        <select
          className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100"
          value={planetId}
          onChange={(e) => setPlanetId(e.target.value)}
        >
          {planets.map((p) => (
            <option key={p.id} value={p.id}>{p.name}</option>
          ))}
        </select>
      </label>

      {/* Our faction (multi-faction support) */}
      <label className="block">
        <span className="block text-sm font-medium text-parchment-200">Fighting as</span>
        <select
          className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100"
          value={factionId}
          onChange={(e) => setFactionId(e.target.value)}
        >
          {userFactions.length === 0 ? (
            <option value="">(Join a faction first on your dashboard)</option>
          ) : (
            userFactions.map((f) => <option key={f.id} value={f.id}>{f.name}</option>)
          )}
        </select>
      </label>

      {/* System */}
      <label className="block">
        <span className="block text-sm font-medium text-parchment-200">Game System</span>
        <select
          className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100"
          value={systemId}
          onChange={(e) => setSystemId(e.target.value as GameSystemId)}
        >
          {allowedSystems.length === 0 && <option value="">— no systems allowed here —</option>}
          {allowedSystems.map((s) => (
            <option key={s.id} value={s.id}>{s.name}</option>
          ))}
        </select>
        {allowedSystems.length > 0 && allowedSystems.length < systems.length && (
          <p className="mt-1 text-xs text-parchment-400">
            This planet is restricted to {allowedSystems.map((s) => s.short_name).join(', ')}.
          </p>
        )}
      </label>

      {/* Size — only for systems that support it */}
      {currentSystem?.supports_size && (
        <div>
          <span className="block text-sm font-medium text-parchment-200">Battle Size</span>
          <div className="mt-1 grid grid-cols-1 gap-2 sm:grid-cols-3">
            {sizeOptions.map((s) => (
              <button
                key={s}
                type="button"
                onClick={() => setSize(s)}
                className={`rounded border px-3 py-2 text-left text-sm transition-colors ${
                  size === s
                    ? 'border-brass-500 bg-brass-700/30 text-brass-100'
                    : 'border-brass-700/40 bg-parchment-950 text-parchment-200 hover:border-brass-600'
                }`}
              >
                {sizeLabel[s]}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Video game — only for 'video' */}
      {currentSystem?.supports_video_game && (
        <label className="block">
          <span className="block text-sm font-medium text-parchment-200">Video Game</span>
          <select
            className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100"
            value={videoGameId}
            onChange={(e) => setVideoGameId(e.target.value === '' ? '' : Number(e.target.value))}
          >
            <option value="">— select a title —</option>
            {videoGames.map((v) => (
              <option key={v.id} value={v.id}>{v.name}</option>
            ))}
          </select>
        </label>
      )}

      {/* Result */}
      <div>
        <span className="block text-sm font-medium text-parchment-200">Result</span>
        <div className="mt-1 grid grid-cols-3 gap-2">
          {(['loss','draw','win'] as BattleResult[]).map((r) => {
            const pts = schemes.find(
              (s) => s.game_system_id === systemId && s.game_size === size && s.result === r,
            )?.points ?? 0;
            const active = result === r;
            const palette = r === 'win'
              ? (active ? 'border-green-500 bg-green-900/40 text-green-100' : 'border-brass-700/40 text-parchment-200')
              : r === 'loss'
              ? (active ? 'border-red-500 bg-red-900/40 text-red-100' : 'border-brass-700/40 text-parchment-200')
              : (active ? 'border-yellow-500 bg-yellow-900/40 text-yellow-100' : 'border-brass-700/40 text-parchment-200');
            return (
              <button
                key={r}
                type="button"
                onClick={() => setResult(r)}
                className={`flex flex-col items-center rounded border bg-parchment-950 px-3 py-2 text-sm transition-colors hover:border-brass-600 ${palette}`}
              >
                <span className="font-cinzel uppercase tracking-wider">{r}</span>
                <span className="text-xs opacity-80">+{pts} glory</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Computed points preview */}
      <div className="rounded border border-brass-700/40 bg-parchment-900/40 px-3 py-2 text-sm text-parchment-200">
        This submission is worth <span className="font-bold text-brass-100">{points}</span> glory points
        {adversary.userId && (
          <> · opponent earns <span className="font-bold text-brass-100">{Math.max(1, Math.ceil(points / 2))}</span></>
        )}
        {currentSystem && <> · {currentSystem.short_name}</>}
        {currentSystem?.supports_size && <> · {size}</>}
      </div>

      {/* Adversary */}
      <AdversaryPicker
        value={adversary}
        onChange={setAdversary}
        currentUserId={currentUserId}
      />

      {/* Title / description / image */}
      <label className="block">
        <span className="block text-sm font-medium text-parchment-200">Battle title (optional)</span>
        <input
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="The Siege of Vraks"
          className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100 placeholder:text-parchment-500"
        />
      </label>

      <label className="block">
        <span className="block text-sm font-medium text-parchment-200">Description / after-action report</span>
        <textarea
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          rows={4}
          className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100 placeholder:text-parchment-500"
          placeholder="Tell the tale…"
        />
      </label>

      <label className="block">
        <span className="block text-sm font-medium text-parchment-200">Image URL (optional)</span>
        <input
          type="url"
          value={imageUrl}
          onChange={(e) => setImageUrl(e.target.value)}
          placeholder="https://…"
          className="mt-1 w-full rounded border border-brass-700/40 bg-parchment-950 px-3 py-2 text-parchment-100 placeholder:text-parchment-500"
        />
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

/** Return list of systems allowed for a planet. Empty allowlist = all allowed. */
function allowedForPlanet(
  planetId: string,
  planetSystems: Array<{ planet_id: string; game_system_id: GameSystemId }>,
  all: GameSystem[],
): GameSystem[] {
  const rows = planetSystems.filter((r) => r.planet_id === planetId);
  if (rows.length === 0) return all;
  const ids = new Set(rows.map((r) => r.game_system_id));
  return all.filter((s) => ids.has(s.id));
}
