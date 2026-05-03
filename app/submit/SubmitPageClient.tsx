'use client';

// =====================================================================
// app/submit/SubmitPageClient.tsx
// Client wrapper: kind-picker tabs + per-kind forms. Battle uses the
// rich BattleSubmitForm; loremaster (reading/listening) has its own
// dedicated form because it captures format/rating/reflection. Painted
// and Scribe (writing) share the simple form.
// =====================================================================

import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { uploadImage } from '@/lib/upload-image';
import BattleSubmitForm from '@/components/BattleSubmitForm';
import { POINT_PRESETS } from '@/lib/types';
import type { GameSystemId, LoreFormat } from '@/lib/types';

interface Planet  { id: string; name: string; }
interface Faction { id: string; name: string; }

type Kind = 'battle' | 'painted' | 'scribe' | 'loremaster';

interface Props {
  planets: Planet[];
  userFactions: Faction[];
  planetSystems: Array<{ planet_id: string; game_system_id: GameSystemId }>;
  currentUserId: string;
}

const KINDS: Array<{ id: Kind; label: string; icon: string; desc: string }> = [
  { id: 'battle',     label: 'Battle Report', icon: '⚔', desc: 'Log a game and claim glory on a world.' },
  { id: 'painted',    label: 'Painted Unit',  icon: '🖌', desc: 'Share miniatures you finished painting.' },
  { id: 'scribe',     label: 'Scribe',        icon: '📜', desc: 'Write a piece of campaign fiction.' },
  { id: 'loremaster', label: 'Loremaster',    icon: '📖', desc: 'Log a novel or audio drama you read.' },
];

export default function SubmitPageClient({ planets, userFactions, planetSystems, currentUserId }: Props) {
  const [kind, setKind] = useState<Kind>('battle');

  return (
    <div>
      {/* Kind selector */}
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-4">
        {KINDS.map((k) => {
          const active = kind === k.id;
          return (
            <button
              key={k.id}
              type="button"
              onClick={() => setKind(k.id)}
              className={`rounded border px-3 py-3 text-left transition-colors hover:border-brass/50 ${
                active
                  ? 'border-brass bg-brass/10 text-parchment'
                  : 'border-brass/20 text-parchment-dim'
              }`}
            >
              <div className="flex items-center gap-2 font-display text-base">
                <span aria-hidden>{k.icon}</span>
                {k.label}
              </div>
              <p className="mt-1 text-xs text-parchment-dark">{k.desc}</p>
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
        ) : kind === 'loremaster' ? (
          <LoremasterSubmitForm
            planets={planets}
            userFactions={userFactions}
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
// Simple (painted / scribe) form — no game system / adversary fields.
// -----------------------------------------------------------------
function SimpleSubmitForm({
  kind, planets, userFactions, currentUserId,
}: {
  kind: 'painted' | 'scribe';
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
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [points, setPoints] = useState<number>(
    kind === 'painted' ? POINT_PRESETS.model[0].value : POINT_PRESETS.scribe[0].value,
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
    if (kind === 'painted' && !imageFile && !imageUrl.trim()) {
      setError('Painted model submissions require an image (file or URL).');
      return;
    }
    setSubmitting(true);

    let finalImageUrl: string | null = imageUrl.trim() || null;
    if (imageFile) {
      try {
        finalImageUrl = await uploadImage(imageFile);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Image upload failed.');
        setSubmitting(false);
        return;
      }
    }

    // UI tab id 'painted' maps to DB enum 'model'; 'scribe' is itself a DB enum value.
    const dbType = kind === 'painted' ? 'model' : kind;
    const { error: err } = await supabase.from('submissions').insert({
      player_id:  currentUserId,
      type: dbType,
      status:     'pending',
      target_planet_id: planetId,
      faction_id: factionId,
      title:      title.trim() || (kind === 'painted' ? 'Painted model' : 'Lore entry'),
      body:       description.trim() || null,
      image_url:  finalImageUrl,
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
          rows={kind === 'scribe' ? 8 : 4}
          className="input w-full"
        />
      </label>

      <div>
        <span className="label">
          Image {kind === 'painted'
            ? <span className="text-parchment-dark normal-case">(required)</span>
            : <span className="text-parchment-dark normal-case">(optional)</span>}
        </span>
        <input
          type="file"
          accept="image/*"
          onChange={(e) => setImageFile(e.target.files?.[0] ?? null)}
          className="input w-full file:bg-brass-dark file:text-parchment file:border-0 file:px-3 file:py-1 file:mr-3 file:font-display file:uppercase file:text-xs file:tracking-wider"
        />
        <label className="mt-3 block">
          <span className="label">Or paste an image URL</span>
          <input
            type="url"
            value={imageUrl}
            onChange={(e) => setImageUrl(e.target.value)}
            placeholder="https://…"
            className="input w-full"
            disabled={!!imageFile}
          />
        </label>
        {imageFile && (
          <p className="mt-1 text-xs italic text-parchment-dark">
            Uploading {imageFile.name} on submit. Clear the file to use a URL instead.
          </p>
        )}
      </div>

      {kind === 'painted' ? (
        <div>
          <span className="label">Unit Size</span>
          <div className="mt-1 grid grid-cols-1 gap-2 sm:grid-cols-2 md:grid-cols-3">
            {POINT_PRESETS.model.map((opt) => (
              <button
                key={opt.value}
                type="button"
                onClick={() => setPoints(opt.value)}
                className={`flex flex-col items-center rounded border px-3 py-2 text-center text-sm transition-colors hover:border-brass/50 ${
                  points === opt.value
                    ? 'border-brass bg-brass/10 text-parchment'
                    : 'border-brass/20 text-parchment-dim'
                }`}
              >
                <span>{opt.label}</span>
                <span className="text-xs opacity-80">{opt.value} pts</span>
              </button>
            ))}
          </div>
          <p className="mt-1 text-xs italic text-parchment-dark">
            The Inquisition may adjust this value upon review.
          </p>
        </div>
      ) : (
        <div>
          <span className="label">Claimed points</span>
          <div className="mt-1 grid grid-cols-1 gap-2 sm:grid-cols-3">
            {POINT_PRESETS.scribe.map((opt) => (
              <button
                key={opt.value}
                type="button"
                onClick={() => setPoints(opt.value)}
                className={`flex flex-col items-center rounded border px-3 py-2 text-center text-sm transition-colors hover:border-brass/50 ${
                  points === opt.value
                    ? 'border-brass bg-brass/10 text-parchment'
                    : 'border-brass/20 text-parchment-dim'
                }`}
              >
                <span>{opt.label}</span>
                <span className="text-xs opacity-80">{opt.value} pts</span>
              </button>
            ))}
          </div>
          <p className="mt-1 text-xs italic text-parchment-dark">
            The Inquisition may adjust this value upon review.
          </p>
        </div>
      )}

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

// -----------------------------------------------------------------
// Loremaster (reading / listening) form. Captures title, format,
// star rating, and a short reflection. Glory is fixed at 1 point.
// -----------------------------------------------------------------
const REFLECTION_MIN = 50;
const REFLECTION_MAX = 500;

function LoremasterSubmitForm({
  planets, userFactions, currentUserId,
}: {
  planets: Planet[];
  userFactions: Faction[];
  currentUserId: string;
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [planetId, setPlanetId] = useState(planets[0]?.id ?? '');
  const [factionId, setFactionId] = useState(userFactions[0]?.id ?? '');
  const [loreTitle, setLoreTitle] = useState('');
  const [format, setFormat] = useState<LoreFormat>('novel');
  const [rating, setRating] = useState<number>(0);
  const [reflection, setReflection] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reflectionLen = reflection.trim().length;
  const reflectionValid = reflectionLen >= REFLECTION_MIN && reflectionLen <= REFLECTION_MAX;

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (!planetId || !factionId) {
      setError('Planet and faction are required.');
      return;
    }
    if (!loreTitle.trim()) {
      setError('Title is required.');
      return;
    }
    if (rating < 1 || rating > 5) {
      setError('Pick a rating between 1 and 5 stars.');
      return;
    }
    if (!reflectionValid) {
      setError(`Reflection must be ${REFLECTION_MIN}–${REFLECTION_MAX} characters.`);
      return;
    }
    setSubmitting(true);

    let finalImageUrl: string | null = imageUrl.trim() || null;
    if (imageFile) {
      try {
        finalImageUrl = await uploadImage(imageFile);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Image upload failed.');
        setSubmitting(false);
        return;
      }
    }

    const trimmedTitle = loreTitle.trim();
    const trimmedReflection = reflection.trim();

    const { error: err } = await supabase.from('submissions').insert({
      player_id:        currentUserId,
      type:             'loremaster',
      status:           'pending',
      target_planet_id: planetId,
      faction_id:       factionId,
      title:            trimmedTitle,
      body:             trimmedReflection,
      image_url:        finalImageUrl,
      points:           1,
      lore_title:       trimmedTitle,
      lore_format:      format,
      lore_rating:      rating,
      lore_reflection:  trimmedReflection,
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
            <option value="" className="bg-ink text-parchment">(Join a faction first)</option>
          ) : (
            userFactions.map((f) => (
              <option key={f.id} value={f.id} className="bg-ink text-parchment">{f.name}</option>
            ))
          )}
        </select>
      </label>

      <label className="block">
        <span className="label">Title</span>
        <input
          type="text"
          value={loreTitle}
          onChange={(e) => setLoreTitle(e.target.value)}
          className="input w-full"
          placeholder="The Horus Heresy: Horus Rising"
          required
        />
      </label>

      <div>
        <span className="label">Format</span>
        <div className="mt-1 grid grid-cols-1 gap-2 sm:grid-cols-2">
          {([
            { id: 'novel',     label: 'Novel / omnibus',         icon: '📕' },
            { id: 'audiobook', label: 'Audiobook / audio drama', icon: '🎧' },
          ] as const).map((opt) => (
            <button
              key={opt.id}
              type="button"
              onClick={() => setFormat(opt.id)}
              className={`flex items-center justify-center gap-2 rounded border px-3 py-2 text-sm transition-colors hover:border-brass/50 ${
                format === opt.id
                  ? 'border-brass bg-brass/10 text-parchment'
                  : 'border-brass/20 text-parchment-dim'
              }`}
            >
              <span aria-hidden>{opt.icon}</span>
              {opt.label}
            </button>
          ))}
        </div>
      </div>

      <div>
        <span className="label">Rating</span>
        <div className="mt-1 flex items-center gap-1">
          {[1, 2, 3, 4, 5].map((n) => {
            const active = n <= rating;
            return (
              <button
                key={n}
                type="button"
                onClick={() => setRating(n)}
                aria-label={`${n} star${n === 1 ? '' : 's'}`}
                className={`text-2xl transition-colors ${
                  active ? 'text-brass-bright' : 'text-parchment-dark hover:text-brass'
                }`}
              >
                {active ? '★' : '☆'}
              </button>
            );
          })}
          <span className="ml-2 text-xs text-parchment-dark">
            {rating === 0 ? 'Pick a rating' : `${rating} / 5`}
          </span>
        </div>
      </div>

      <label className="block">
        <span className="label">Reflection</span>
        <p className="mb-1 text-xs italic text-parchment-dark">
          In a sentence or two, what stuck with you? A revelation about your faction, a memorable
          character moment, or a piece of lore that changes how you see the galaxy…
        </p>
        <textarea
          value={reflection}
          onChange={(e) => setReflection(e.target.value)}
          rows={5}
          className="input w-full"
          minLength={REFLECTION_MIN}
          maxLength={REFLECTION_MAX}
          required
        />
        <p className={`mt-1 text-xs ${reflectionValid || reflectionLen === 0 ? 'text-parchment-dark' : 'text-blood'}`}>
          {reflectionLen} / {REFLECTION_MAX} characters {reflectionLen < REFLECTION_MIN && `(min ${REFLECTION_MIN})`}
        </p>
      </label>

      <div>
        <span className="label">
          Image <span className="text-parchment-dark normal-case">(optional — book cover, Audible screenshot, etc.)</span>
        </span>
        <input
          type="file"
          accept="image/*"
          onChange={(e) => setImageFile(e.target.files?.[0] ?? null)}
          className="input w-full file:bg-brass-dark file:text-parchment file:border-0 file:px-3 file:py-1 file:mr-3 file:font-display file:uppercase file:text-xs file:tracking-wider"
        />
        <label className="mt-3 block">
          <span className="label">Or paste an image URL</span>
          <input
            type="url"
            value={imageUrl}
            onChange={(e) => setImageUrl(e.target.value)}
            placeholder="https://…"
            className="input w-full"
            disabled={!!imageFile}
          />
        </label>
        {imageFile && (
          <p className="mt-1 text-xs italic text-parchment-dark">
            Uploading {imageFile.name} on submit. Clear the file to use a URL instead.
          </p>
        )}
      </div>

      <p className="text-xs italic text-parchment-dark">
        Lore deeds are worth a fixed 1 glory.
      </p>

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
