// =====================================================================
// app/page.tsx — REPLACEMENT home page.
// Keeps your existing hero/intro feel but adds the activity feed below.
// Tweak the hero copy to match your current home page if you've edited it.
// =====================================================================

import Link from 'next/link';
import ActivityFeed from '@/components/ActivityFeed';

export const revalidate = 30; // refresh feed every 30s for visitors

export default function HomePage() {
  return (
    <main className="mx-auto max-w-6xl px-4 pb-16 pt-8 sm:px-6 sm:pt-12">
      {/* Hero */}
      <section className="relative overflow-hidden rounded border border-brass-700/40 bg-gradient-to-b from-parchment-900/70 to-parchment-950 p-6 sm:p-10">
        <div className="pointer-events-none absolute inset-0 opacity-20" aria-hidden>
          <div className="absolute -right-20 -top-20 h-80 w-80 rounded-full bg-brass-500 blur-3xl" />
        </div>
        <div className="relative">
          <p className="font-cinzel text-xs uppercase tracking-[0.3em] text-brass-300">
            ✠ The Crusade Ledger ✠
          </p>
          <h1 className="mt-2 font-cinzel text-3xl text-brass-100 sm:text-5xl">
            Record your victories.<br className="hidden sm:block" /> Claim the stars.
          </h1>
          <p className="mt-4 max-w-2xl text-base text-parchment-200 sm:text-lg">
            A grimdark campaign ledger for Warhammer 40,000 gaming groups. Submit battle reports,
            painted models, and tales of war; earn glory for your faction; watch worlds fall under your banner.
          </p>
          <div className="mt-5 flex flex-wrap gap-3">
            <Link
              href="/submit"
              className="rounded border border-brass-500 bg-brass-700/40 px-4 py-2 font-cinzel text-brass-100 hover:bg-brass-600/40"
            >
              Submit a Deed
            </Link>
            <Link
              href="/map"
              className="rounded border border-brass-700/40 bg-parchment-950 px-4 py-2 font-cinzel text-parchment-100 hover:border-brass-500"
            >
              View the Map
            </Link>
            <Link
              href="/leaderboard"
              className="rounded border border-brass-700/40 bg-parchment-950 px-4 py-2 font-cinzel text-parchment-100 hover:border-brass-500"
            >
              Leaderboard
            </Link>
          </div>
        </div>
      </section>

      {/* Activity feed */}
      <section className="mt-10">
        <div className="flex items-end justify-between gap-2">
          <h2 className="font-cinzel text-2xl text-brass-100">Recent Deeds</h2>
          <Link href="/leaderboard" className="text-sm text-brass-300 hover:text-brass-100">
            Leaderboard →
          </Link>
        </div>
        <p className="mt-1 text-sm text-parchment-300">
          Battles fought, models painted, and tales told — as approved by the inquisition.
        </p>
        <div className="mt-4">
          {/* Server component handles data fetching. */}
          <ActivityFeed limit={15} />
        </div>
      </section>
    </main>
  );
}
