// =====================================================================
// app/dashboard/page.tsx — REPLACEMENT (or merge these sections into
// your existing dashboard).
//
// Shows:
//   * User's faction memberships (multi-faction manager)
//   * User's own ELO ratings
//   * User's recent submissions with status
//   * User's earned/in-progress/locked awards
// =====================================================================

import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import FactionMembership from '@/components/FactionMembership';
import KindBadge from '@/components/KindBadge';
import AwardCard from '@/components/AwardCard';
import AwardToaster from '@/components/AwardToaster';
import HonoursStrip, { type FeaturedAward } from '@/components/HonoursStrip';
import { DashboardProfile } from './DashboardProfile';
import type { Award, AwardCategory, PlayerAward, Profile } from '@/lib/types';
import { AWARD_CATEGORY_LABELS } from '@/lib/types';

export const dynamic = 'force-dynamic';

interface EloRow {
  game_system_id: string;
  faction_id: string;
  rating: number;
  games_played: number;
  wins: number;
  losses: number;
  draws: number;
  factions: { name: string; color: string | null } | null;
  game_systems: { short_name: string; name: string } | null;
}

interface SubRow {
  id: string;
  kind: string;
  status: string;
  title: string | null;
  points: number | null;
  created_at: string;
  planets: { name: string } | null;
}

const CATEGORY_ORDER: AwardCategory[] = ['combat', 'painting', 'lore', 'conquest', 'cross'];

// Count-based awards: key -> target count and which counter feeds it.
const PROGRESS_TARGETS: Record<string, { target: number; counter: 'game' | 'model' | 'scribe' | 'loremaster' | 'distinct_types' }> = {
  first_blood:                 { target: 1,   counter: 'game' },
  veteran:                     { target: 3,   counter: 'game' },
  honored_of_the_chapter:      { target: 10,  counter: 'game' },
  warmaster:                   { target: 20,  counter: 'game' },
  brush_initiate:              { target: 1,   counter: 'model' },
  production_painter:          { target: 3,   counter: 'model' },
  master_artisan:              { target: 10,  counter: 'model' },
  painting_daemon:             { target: 20,  counter: 'model' },
  remembrancer:                { target: 1,   counter: 'scribe' },
  chronicler:                  { target: 3,   counter: 'scribe' },
  master_scribe:               { target: 10,  counter: 'scribe' },
  keeper_of_secrets:           { target: 20,  counter: 'scribe' },
  witness_of_the_word:         { target: 15,  counter: 'loremaster' },
  keeper_of_the_black_library: { target: 100, counter: 'loremaster' },
  accept_any_challenge:        { target: 4,   counter: 'distinct_types' },
};

export default async function DashboardPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect('/auth/login?next=/dashboard');

  const [profileRes, eloRes, subsRes, awardsRes, playerAwardsRes, gameCountRes, modelCountRes, scribeCountRes, loremasterCountRes] = await Promise.all([
    supabase
      .from('profiles')
      .select('id, display_name, faction_id, email, avatar_url, is_admin, created_at')
      .eq('id', user.id)
      .maybeSingle(),
    supabase
      .from('elo_ratings')
      .select('game_system_id, faction_id, rating, games_played, wins, losses, draws, factions(name, color), game_systems(short_name, name)')
      .eq('user_id', user.id)
      .order('rating', { ascending: false }),
    supabase
      .from('submissions')
      .select('id, kind:type, status, title, points, created_at, planets(name)')
      .eq('player_id', user.id)
      .order('created_at', { ascending: false })
      .limit(25),
    supabase
      .from('awards')
      .select('id, key, name, description, hint, tier, category, icon, sort_order')
      .order('sort_order', { ascending: true }),
    supabase
      .from('player_awards')
      .select('id, player_id, award_id, earned_at, is_featured, notified')
      .eq('player_id', user.id),
    supabase
      .from('submissions')
      .select('id', { count: 'exact', head: true })
      .eq('player_id', user.id).eq('type', 'game').eq('status', 'approved'),
    supabase
      .from('submissions')
      .select('id', { count: 'exact', head: true })
      .eq('player_id', user.id).eq('type', 'model').eq('status', 'approved'),
    supabase
      .from('submissions')
      .select('id', { count: 'exact', head: true })
      .eq('player_id', user.id).eq('type', 'scribe').eq('status', 'approved'),
    supabase
      .from('submissions')
      .select('id', { count: 'exact', head: true })
      .eq('player_id', user.id).eq('type', 'loremaster').eq('status', 'approved'),
  ]);

  const profile = (profileRes.data ?? null) as Profile | null;
  const elo  = (eloRes.data ?? []) as unknown as EloRow[];
  const subs = (subsRes.data ?? []) as unknown as SubRow[];
  const awards = (awardsRes.data ?? []) as Award[];
  const playerAwards = (playerAwardsRes.data ?? []) as PlayerAward[];

  const gameCount       = gameCountRes.count       ?? 0;
  const modelCount      = modelCountRes.count      ?? 0;
  const scribeCount     = scribeCountRes.count     ?? 0;
  const loremasterCount = loremasterCountRes.count ?? 0;
  // Bonus is admin-only and excluded from Accept Any Challenge.
  const distinctTypes = [gameCount, modelCount, scribeCount, loremasterCount].filter((n) => n > 0).length;

  const counters = { game: gameCount, model: modelCount, scribe: scribeCount, loremaster: loremasterCount, distinct_types: distinctTypes };
  const earnedById = new Map(playerAwards.map((pa) => [pa.award_id, pa]));

  const featured: FeaturedAward[] = playerAwards
    .filter((pa) => pa.is_featured)
    .map((pa) => {
      const a = awards.find((x) => x.id === pa.award_id);
      return a ? { player_award: pa, award: a } : null;
    })
    .filter((x): x is FeaturedAward => x !== null);

  const awardsByCategory = new Map<AwardCategory, Award[]>();
  for (const a of awards) {
    const list = awardsByCategory.get(a.category) ?? [];
    list.push(a);
    awardsByCategory.set(a.category, list);
  }

  return (
    <main className="mx-auto max-w-5xl px-4 py-6 sm:px-6 sm:py-10">
      <AwardToaster userId={user.id} />

      <header className="flex items-center gap-3">
        <div className="h-14 w-14 overflow-hidden rounded-full border border-brass/50 bg-ink-2">
          {profile?.avatar_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={profile.avatar_url}
              alt={profile.display_name ?? 'Avatar'}
              className="h-full w-full object-cover"
            />
          ) : (
            <div className="flex h-full w-full items-center justify-center font-display text-xl text-brass">
              {(profile?.display_name ?? '?').charAt(0).toUpperCase()}
            </div>
          )}
        </div>
        <div>
          <p className="font-display text-xs uppercase tracking-[0.3em] text-brass">
            ✠ Your Dashboard ✠
          </p>
          <h1 className="font-display text-2xl tracking-widest text-parchment sm:text-3xl">
            {profile?.display_name ?? 'Commander'}
          </h1>
        </div>
        <Link
          href={`/player/${user.id}`}
          className="ml-auto rounded border border-brass/40 px-3 py-1.5 text-sm text-parchment-dim transition-colors hover:border-brass hover:text-brass-bright"
        >
          View public profile →
        </Link>
      </header>

      {/* Pinned honours hero strip */}
      <HonoursStrip featured={featured} />

      {/* Profile editor */}
      {profile && (
        <div className="mt-6">
          <DashboardProfile profile={profile} />
        </div>
      )}

      {/* Faction memberships */}
      <div className="mt-6">
        <FactionMembership userId={user.id} />
      </div>

      {/* ELO */}
      <section className="card p-6 mt-6">
        <div className="font-display uppercase tracking-widest text-xs text-brass mb-2">
          Your Ratings
        </div>
        {elo.length === 0 ? (
          <p className="text-sm text-parchment-dim italic">
            No rated games yet. Link an adversary when you submit a battle and both players earn ELO when approved.
          </p>
        ) : (
          <div className="mt-3 overflow-x-auto">
            <table className="w-full min-w-[500px] text-sm">
              <thead>
                <tr className="border-b border-brass/20 text-xs font-display uppercase tracking-wider text-brass">
                  <th className="text-left p-2">System</th>
                  <th className="text-left p-2">Faction</th>
                  <th className="text-right p-2">Rating</th>
                  <th className="text-right p-2">W</th>
                  <th className="text-right p-2">L</th>
                  <th className="text-right p-2">D</th>
                </tr>
              </thead>
              <tbody>
                {elo.map((r) => (
                  <tr key={`${r.game_system_id}-${r.faction_id}`} className="border-b border-brass/5">
                    <td className="p-2 text-parchment">{r.game_systems?.short_name ?? r.game_system_id}</td>
                    <td className="p-2">
                      <span className="inline-flex items-center gap-2 text-parchment">
                        <span
                          className="inline-block h-2.5 w-2.5 rounded-full"
                          style={{ backgroundColor: r.factions?.color ?? '#7a5b20' }}
                        />
                        {r.factions?.name ?? r.faction_id}
                      </span>
                    </td>
                    <td className="p-2 text-right font-display text-brass-bright">{r.rating}</td>
                    <td className="p-2 text-right text-green-300">{r.wins}</td>
                    <td className="p-2 text-right text-red-300">{r.losses}</td>
                    <td className="p-2 text-right text-yellow-300">{r.draws}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* Honours */}
      <section className="card p-6 mt-6">
        <div className="font-display uppercase tracking-widest text-xs text-brass mb-3">
          Your Honors
        </div>
        <p className="text-xs text-parchment-dim italic mb-4">
          Awards are derived from approved submissions. Pin up to three to display at the top of your dashboard.
        </p>
        {CATEGORY_ORDER.map((cat) => {
          const list = awardsByCategory.get(cat) ?? [];
          if (list.length === 0) return null;
          return (
            <div key={cat} className="mt-4 first:mt-0">
              <div className="font-display text-[11px] uppercase tracking-widest text-brass-bright mb-2">
                {AWARD_CATEGORY_LABELS[cat]}
              </div>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {list.map((a) => {
                  const earned = earnedById.get(a.id) ?? null;
                  const cfg = PROGRESS_TARGETS[a.key];
                  const progress = !earned && cfg
                    ? { current: counters[cfg.counter], target: cfg.target }
                    : null;
                  return (
                    <AwardCard
                      key={a.id}
                      award={a}
                      earned={earned}
                      progress={progress}
                      showFeaturedToggle
                    />
                  );
                })}
              </div>
            </div>
          );
        })}
      </section>

      {/* Submissions */}
      <section className="card p-6 mt-6">
        <div className="flex items-center justify-between gap-2 mb-2">
          <div className="font-display uppercase tracking-widest text-xs text-brass">
            Your Submissions
          </div>
          <Link
            href="/submit"
            className="rounded border border-brass/60 bg-brass/20 px-2.5 py-1 text-xs font-display uppercase tracking-wider text-brass-bright transition-colors hover:bg-brass/30"
          >
            Submit a Deed
          </Link>
        </div>
        {subs.length === 0 ? (
          <p className="text-sm text-parchment-dim italic">No submissions yet.</p>
        ) : (
          <ul className="mt-3 flex flex-col divide-y divide-brass/10">
            {subs.map((s) => (
              <li key={s.id} className="group relative flex flex-wrap items-center gap-2 px-2 py-2 text-sm transition-colors hover:bg-brass/5">
                {/* Stretched overlay sits on top so clicks anywhere on the row navigate.
                    No inner links exist here, so a single overlay is sufficient. */}
                <Link
                  href={`/submission/${s.id}`}
                  aria-label={`View deed: ${s.title ?? s.kind}`}
                  className="absolute inset-0 z-10 focus:outline-none focus-visible:ring-2 focus-visible:ring-brass focus-visible:ring-inset"
                />
                <KindBadge kind={s.kind} />
                <span className="text-parchment transition-colors group-hover:text-brass-bright">{s.title ?? '(untitled)'}</span>
                {s.planets?.name && (
                  <span className="text-parchment-dim">· {s.planets.name}</span>
                )}
                <span className={`ml-auto rounded px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider ${
                  s.status === 'approved' ? 'bg-green-900/40 text-green-200'
                  : s.status === 'rejected' ? 'bg-red-900/40 text-red-200'
                  : 'bg-yellow-900/40 text-yellow-200'
                }`}>
                  {s.status}
                </span>
                {s.points !== null && (
                  <span className="text-xs text-brass-bright">+{s.points}</span>
                )}
                <span className="w-full text-right text-[10px] text-parchment-dark sm:w-auto">
                  {new Date(s.created_at).toLocaleDateString()}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

    </main>
  );
}
