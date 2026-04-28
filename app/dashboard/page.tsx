// =====================================================================
// app/dashboard/page.tsx — REPLACEMENT (or merge these sections into
// your existing dashboard).
//
// Shows:
//   * User's faction memberships (multi-faction manager)
//   * User's own ELO ratings
//   * User's recent submissions with status
// =====================================================================

import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import FactionMembership from '@/components/FactionMembership';
import KindBadge from '@/components/KindBadge';

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

export default async function DashboardPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect('/auth/login?next=/dashboard');

  const [profileRes, eloRes, subsRes] = await Promise.all([
    supabase.from('profiles').select('display_name').eq('id', user.id).maybeSingle(),
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
  ]);

  const profile = profileRes.data as { display_name: string | null } | null;
  const elo  = (eloRes.data ?? []) as unknown as EloRow[];
  const subs = (subsRes.data ?? []) as unknown as SubRow[];

  return (
    <main className="mx-auto max-w-5xl px-4 py-6 sm:px-6 sm:py-10">
      <header className="flex items-center gap-3">
        <div className="h-14 w-14 overflow-hidden rounded-full border border-brass-700/50 bg-parchment-800">
          <div className="flex h-full w-full items-center justify-center font-cinzel text-xl text-brass-300">
            {(profile?.display_name ?? '?').charAt(0).toUpperCase()}
          </div>
        </div>
        <div>
          <p className="font-cinzel text-xs uppercase tracking-[0.3em] text-brass-300">
            ✠ Your Dashboard ✠
          </p>
          <h1 className="font-cinzel text-2xl text-brass-100 sm:text-3xl">
            {profile?.display_name ?? 'Commander'}
          </h1>
        </div>
        <Link
          href={`/player/${user.id}`}
          className="ml-auto rounded border border-brass-700/40 px-3 py-1.5 text-sm text-parchment-200 hover:text-brass-100"
        >
          View public profile →
        </Link>
      </header>

      {/* Faction memberships */}
      <div className="mt-6">
        <FactionMembership userId={user.id} />
      </div>

      {/* ELO */}
      <section className="mt-6 rounded border border-brass-700/40 bg-parchment-900/40 p-4">
        <h2 className="font-cinzel text-lg text-brass-100">Your Ratings</h2>
        {elo.length === 0 ? (
          <p className="mt-1 text-sm text-parchment-400">
            No rated games yet. Link an adversary when you submit a battle and both players earn ELO when approved.
          </p>
        ) : (
          <div className="mt-3 overflow-x-auto">
            <table className="w-full min-w-[500px] text-sm">
              <thead className="text-left font-cinzel text-brass-200">
                <tr>
                  <th className="px-2 py-1">System</th>
                  <th className="px-2 py-1">Faction</th>
                  <th className="px-2 py-1 text-right">Rating</th>
                  <th className="px-2 py-1 text-right">W</th>
                  <th className="px-2 py-1 text-right">L</th>
                  <th className="px-2 py-1 text-right">D</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-brass-700/20">
                {elo.map((r) => (
                  <tr key={`${r.game_system_id}-${r.faction_id}`} className="text-parchment-200">
                    <td className="px-2 py-1.5">{r.game_systems?.short_name ?? r.game_system_id}</td>
                    <td className="px-2 py-1.5">
                      <span className="inline-flex items-center gap-2">
                        <span
                          className="inline-block h-2.5 w-2.5 rounded-full"
                          style={{ backgroundColor: r.factions?.color ?? '#7a5b20' }}
                        />
                        {r.factions?.name ?? r.faction_id}
                      </span>
                    </td>
                    <td className="px-2 py-1.5 text-right font-bold text-brass-100">{r.rating}</td>
                    <td className="px-2 py-1.5 text-right text-green-300">{r.wins}</td>
                    <td className="px-2 py-1.5 text-right text-red-300">{r.losses}</td>
                    <td className="px-2 py-1.5 text-right text-yellow-300">{r.draws}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* Submissions */}
      <section className="mt-6 rounded border border-brass-700/40 bg-parchment-900/40 p-4">
        <div className="flex items-center justify-between gap-2">
          <h2 className="font-cinzel text-lg text-brass-100">Your Submissions</h2>
          <Link
            href="/submit"
            className="rounded border border-brass-500 bg-brass-700/30 px-2.5 py-1 text-xs font-cinzel text-brass-100 hover:bg-brass-600/40"
          >
            Submit a Deed
          </Link>
        </div>
        {subs.length === 0 ? (
          <p className="mt-1 text-sm text-parchment-400">No submissions yet.</p>
        ) : (
          <ul className="mt-3 flex flex-col divide-y divide-brass-700/20">
            {subs.map((s) => (
              <li key={s.id} className="group relative flex flex-wrap items-center gap-2 px-2 py-2 text-sm transition-colors hover:bg-brass/10">
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
                  <span className="text-parchment-400">· {s.planets.name}</span>
                )}
                <span className={`ml-auto rounded px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider ${
                  s.status === 'approved' ? 'bg-green-900/40 text-green-200'
                  : s.status === 'rejected' ? 'bg-red-900/40 text-red-200'
                  : 'bg-yellow-900/40 text-yellow-200'
                }`}>
                  {s.status}
                </span>
                {s.points !== null && (
                  <span className="text-xs text-brass-300">+{s.points}</span>
                )}
                <span className="w-full text-right text-[10px] text-parchment-400 sm:w-auto">
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
