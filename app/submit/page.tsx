// =====================================================================
// app/submit/page.tsx — REPLACEMENT submit page.
//
// Loads reference data server-side (planets, user's factions, per-planet
// system allowlist) and hands it off to a client wrapper that lets the
// user pick which kind of submission they're making.
//
// 'battle' uses BattleSubmitForm; 'loremaster' has its own form for
// format/rating/reflection; 'painted' and 'scribe' share SimpleSubmitForm.
// =====================================================================

import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import SubmitPageClient from './SubmitPageClient';
import type { GameSystemId } from '@/lib/types';

export const dynamic = 'force-dynamic';

interface Planet  { id: string; name: string; }
interface Faction { id: string; name: string; }

export default async function SubmitPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect('/auth/login?next=/submit');

  const [planetsRes, pfRes, systemsRes] = await Promise.all([
    supabase.from('planets').select('id, name').order('name'),
    supabase
      .from('player_factions')
      .select('faction_id, is_primary, factions(id, name)')
      .eq('user_id', user.id),
    supabase.from('planet_game_systems').select('planet_id, game_system_id'),
  ]);

  const planets = (planetsRes.data ?? []) as Planet[];

  type PFRow = { faction_id: string; is_primary: boolean; factions: { id: string; name: string } | null };
  const pfRows = (pfRes.data ?? []) as unknown as PFRow[];
  let userFactions: Faction[] = pfRows
    .map((r) => r.factions)
    .filter((f): f is { id: string; name: string } => !!f);

  // Fallback: if no player_factions rows exist yet, read profile.faction_id
  if (userFactions.length === 0) {
    const { data: prof } = await supabase
      .from('profiles')
      .select('faction_id, factions(id, name)')
      .eq('id', user.id)
      .maybeSingle();
    const pf = (prof as unknown as { factions: { id: string; name: string } | null } | null)?.factions;
    if (pf) userFactions = [pf];
  }

  const planetSystems = (systemsRes.data ?? []) as Array<{
    planet_id: string;
    game_system_id: GameSystemId;
  }>;

  return (
    <main className="mx-auto max-w-3xl px-4 py-6 sm:px-6 sm:py-10">
      <header>
        <p className="font-display text-xs uppercase tracking-[0.3em] text-brass">
          ✠ Submit a Deed ✠
        </p>
        <h1 className="mt-1 font-display text-3xl text-parchment">Chronicle Your Contribution</h1>
        <p className="mt-2 font-body text-sm text-parchment-dim">
          All submissions await inquisitorial review. Glory is awarded once approved.
        </p>
      </header>

      {userFactions.length === 0 && (
        <div className="mt-4 rounded border border-crusade bg-crusade/10 p-3 text-sm text-parchment">
          You&apos;re not pledged to a faction yet. Visit your{' '}
          <a href="/dashboard" className="underline">dashboard</a> to join one before submitting deeds.
        </div>
      )}

      <div className="mt-6">
        <SubmitPageClient
          planets={planets}
          userFactions={userFactions}
          planetSystems={planetSystems}
          currentUserId={user.id}
        />
      </div>
    </main>
  );
}
