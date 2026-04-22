// =====================================================================
// app/player/[id]/page.tsx
// Public player profile — accessible to any visitor. Shows:
//   * Identity (display name, avatar, primary faction)
//   * Faction memberships
//   * ELO ratings grouped by game system × faction
//   * Recent approved contributions (battles / painted / lore)
// =====================================================================

import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createServerClient } from '@/lib/supabase/server';
import type { ActivityFeedItem } from '@/lib/types';

interface PageProps {
  params: Promise<{ id: string }>;
}

interface ProfileRow {
  id: string;
  display_name: string | null;
  avatar_url: string | null;
  faction_id: string | null;
  created_at: string;
}

interface FactionMembership {
  faction_id: string;
  is_primary: boolean;
  factions: { id: string; name: string; color: string | null } | null;
}

interface EloRow {
  game_system_id: string;
  faction_id: string;
  rating: number;
  games_played: number;
  wins: number;
  losses: number;
  draws: number;
  factions: { name: string; color: string | null } | null;
  game_systems: { name: string; short_name: string } | null;
}

export default async function PlayerProfilePage({ params }: PageProps) {
  const { id } = await params;
  const supabase = await createServerClient();

  const { data: profile } = await supabase
    .from('profiles')
    .select('id, display_name, avatar_url, faction_id, created_at')
    .eq('id', id)
    .maybeSingle();

  if (!profile) notFound();
  const p = profile as ProfileRow;

  const [memberships, elo, activity, statsRes] = await Promise.all([
    supabase
      .from('player_factions')
      .select('faction_id, is_primary, factions(id, name, color)')
      .eq('user_id', id),
    supabase
      .from('elo_ratings')
      .select('game_system_id, faction_id, rating, games_played, wins, losses, draws, factions(name, color), game_systems(name, short_name)')
      .eq('user_id', id)
      .order('rating', { ascending: false }),
    supabase
      .from('activity_feed')
      .select('*')
      .eq('user_id', id)
      .order('created_at', { ascending: false })
      .limit(25),
    supabase
      .from('submissions')
      .select('kind, points', { count: 'exact' })
      .eq('user_id', id)
      .eq('status', 'approved'),
  ]);

  const memberRows  = (memberships.data ?? []) as unknown as FactionMembership[];
  const eloRows     = (elo.data ?? [])         as unknown as EloRow[];
  const activityRows = (activity.data ?? [])   as unknown as ActivityFeedItem[];

  const approvedSubs = (statsRes.data ?? []) as Array<{ kind: string; points: number | null }>;
  const totalGlory = approvedSubs.reduce((acc, r) => acc + (r.points ?? 0), 0);
  const byKind: Record<string, number> = {};
  for (const s of approvedSubs) byKind[s.kind] = (byKind[s.kind] ?? 0) + 1;

  const primary = memberRows.find((m) => m.is_primary)?.factions;

  return (
    <main className="mx-auto max-w-6xl px-4 py-6 sm:px-6 sm:py-10">
      {/* Header */}
      <header className="flex flex-col items-start gap-4 rounded border border-brass-700/40 bg-parchment-900/50 p-4 sm:flex-row sm:items-center sm:p-6">
        <div className="h-20 w-20 shrink-0 overflow-hidden rounded-full border border-brass-700/50 bg-parchment-800">
          {p.avatar_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={p.avatar_url} alt={p.display_name ?? 'Player'} className="h-full w-full object-cover" />
          ) : (
            <div className="flex h-full w-full items-center justify-center font-cinzel text-2xl text-brass-300">
              {(p.display_name ?? '?').charAt(0).toUpperCase()}
            </div>
          )}
        </div>
        <div className="flex-1">
          <h1 className="font-cinzel text-2xl text-brass-100 sm:text-3xl">
            {p.display_name ?? 'Unknown Commander'}
          </h1>
          {primary && (
            <div className="mt-1 inline-flex items-center gap-2 text-sm text-parchment-200">
              <span
                className="inline-block h-3 w-3 rounded-full"
                style={{ backgroundColor: primary.color ?? '#7a5b20' }}
                aria-hidden
              />
              Champion of <strong>{primary.name}</strong>
            </div>
          )}
          <p className="mt-1 text-xs text-parchment-400">
            Enlisted {new Date(p.created_at).toLocaleDateString()}
          </p>
        </div>

        {/* Summary stats */}
        <div className="grid grid-cols-3 gap-3 text-center">
          <StatBlock label="Glory" value={totalGlory} />
          <StatBlock label="Battles" value={byKind.battle ?? 0} />
          <StatBlock label="Deeds"   value={approvedSubs.length} />
        </div>
      </header>

      {/* Memberships */}
      {memberRows.length > 0 && (
        <section className="mt-6">
          <h2 className="font-cinzel text-xl text-brass-100">Banners Pledged</h2>
          <ul className="mt-3 flex flex-wrap gap-2">
            {memberRows.map((m) => m.factions && (
              <li
                key={m.faction_id}
                className="inline-flex items-center gap-2 rounded border border-brass-700/40 bg-parchment-950 px-3 py-1.5 text-sm"
              >
                <span
                  className="inline-block h-3 w-3 rounded-full"
                  style={{ backgroundColor: m.factions.color ?? '#7a5b20' }}
                  aria-hidden
                />
                <span className="text-parchment-100">{m.factions.name}</span>
                {m.is_primary && (
                  <span className="rounded border border-brass-600 bg-brass-700/30 px-1.5 text-[10px] font-bold uppercase tracking-wider text-brass-100">
                    Primary
                  </span>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* ELO */}
      <section className="mt-8">
        <h2 className="font-cinzel text-xl text-brass-100">Ratings</h2>
        <p className="mt-1 text-sm text-parchment-300">
          ELO is tracked per game system and faction. Opponents must be linked on submission for rating changes.
        </p>
        {eloRows.length === 0 ? (
          <p className="mt-3 text-sm text-parchment-400">No rated games yet.</p>
        ) : (
          <div className="mt-3 overflow-x-auto rounded border border-brass-700/40">
            <table className="w-full min-w-[560px] text-sm">
              <thead className="bg-parchment-900/70 text-left font-cinzel text-brass-200">
                <tr>
                  <th className="px-3 py-2">System</th>
                  <th className="px-3 py-2">Faction</th>
                  <th className="px-3 py-2 text-right">Rating</th>
                  <th className="px-3 py-2 text-right">Games</th>
                  <th className="px-3 py-2 text-right">W</th>
                  <th className="px-3 py-2 text-right">L</th>
                  <th className="px-3 py-2 text-right">D</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-brass-700/20">
                {eloRows.map((r) => (
                  <tr key={`${r.game_system_id}-${r.faction_id}`} className="text-parchment-200">
                    <td className="px-3 py-2">{r.game_systems?.short_name ?? r.game_system_id}</td>
                    <td className="px-3 py-2">
                      <span className="inline-flex items-center gap-2">
                        <span
                          className="inline-block h-2.5 w-2.5 rounded-full"
                          style={{ backgroundColor: r.factions?.color ?? '#7a5b20' }}
                        />
                        {r.factions?.name ?? r.faction_id}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-right font-bold text-brass-100">{r.rating}</td>
                    <td className="px-3 py-2 text-right">{r.games_played}</td>
                    <td className="px-3 py-2 text-right text-green-300">{r.wins}</td>
                    <td className="px-3 py-2 text-right text-red-300">{r.losses}</td>
                    <td className="px-3 py-2 text-right text-yellow-300">{r.draws}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* Recent activity */}
      <section className="mt-8">
        <h2 className="font-cinzel text-xl text-brass-100">Chronicle</h2>
        {activityRows.length === 0 ? (
          <p className="mt-2 text-sm text-parchment-400">No approved deeds yet.</p>
        ) : (
          <ul className="mt-3 flex flex-col gap-3">
            {activityRows.map((a) => (
              <li
                key={a.submission_id}
                className="rounded border border-brass-700/40 bg-parchment-900/50 p-3"
              >
                <div className="flex flex-wrap items-center gap-2 text-xs text-parchment-300">
                  <span className="rounded bg-brass-700/30 px-1.5 py-0.5 font-bold uppercase tracking-wider text-brass-100">
                    {a.kind}
                  </span>
                  {a.game_system_short && (
                    <span className="rounded border border-brass-700/40 px-1.5 py-0.5 uppercase">
                      {a.game_system_short}
                    </span>
                  )}
                  {a.result && (
                    <span className={`rounded px-1.5 py-0.5 uppercase ${
                      a.result === 'win' ? 'bg-green-900/40 text-green-200'
                      : a.result === 'loss' ? 'bg-red-900/40 text-red-200'
                      : 'bg-yellow-900/40 text-yellow-200'
                    }`}>
                      {a.result}
                    </span>
                  )}
                  {a.planet_name && (
                    <Link href={`/map?planet=${a.planet_id}`} className="text-brass-300 hover:text-brass-100">
                      ◈ {a.planet_name}
                    </Link>
                  )}
                  {a.adversary_name && (
                    <span>
                      vs{' '}
                      <Link
                        href={a.adversary_user_id ? `/player/${a.adversary_user_id}` : '#'}
                        className="text-brass-300 hover:text-brass-100"
                      >
                        {a.adversary_name}
                      </Link>
                    </span>
                  )}
                  <span className="ml-auto text-parchment-400">
                    {new Date(a.created_at).toLocaleDateString()}
                  </span>
                </div>
                {a.title && <p className="mt-1 font-cinzel text-parchment-100">{a.title}</p>}
                {a.description && <p className="mt-1 text-sm text-parchment-300">{a.description}</p>}
              </li>
            ))}
          </ul>
        )}
      </section>
    </main>
  );
}

function StatBlock({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded border border-brass-700/40 bg-parchment-950 px-3 py-2">
      <div className="font-cinzel text-xl text-brass-100">{value}</div>
      <div className="text-[10px] uppercase tracking-wider text-parchment-400">{label}</div>
    </div>
  );
}
