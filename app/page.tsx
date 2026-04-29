import Link from 'next/link';
import ActivityFeed from '@/components/ActivityFeed';

export const revalidate = 30;

export default function HomePage() {
  return (
    <main className="mx-auto max-w-6xl px-4 pb-16 pt-8 sm:px-6 sm:pt-12">
      <section className="card relative overflow-hidden p-6 sm:p-10">
        <div className="pointer-events-none absolute inset-0 opacity-20" aria-hidden>
          <div className="absolute -right-20 -top-20 h-80 w-80 rounded-full bg-brass blur-3xl" />
        </div>
        <div className="relative">
          <p className="font-display text-xs uppercase tracking-[0.3em] text-brass">
            ✠ The Campaign Chronicle ✠
          </p>
          <h1 className="mt-2 font-display text-3xl text-parchment sm:text-5xl">
            Record your victories.<br className="hidden sm:block" /> Claim the stars.
          </h1>
          <p className="mt-4 max-w-2xl font-body text-base text-parchment-dim sm:text-lg">
            A grimdark campaign ledger for Warhammer 40,000 gaming groups. Submit battle reports,
            painted models, and tales of war; earn glory for your faction; watch worlds fall under your banner.
          </p>
          <div className="mt-5 flex flex-wrap gap-3">
            <Link href="/submit" className="btn-primary">
              Submit a Deed
            </Link>
            <Link href="/map" className="btn-ghost">
              View the Map
            </Link>
            <Link href="/leaderboard" className="btn-ghost">
              Leaderboard
            </Link>
          </div>
        </div>
      </section>

      <section className="mt-10">
        <div className="flex items-end justify-between gap-2">
          <h2 className="font-display text-2xl text-parchment">Recent Deeds</h2>
          <Link href="/leaderboard" className="text-sm text-brass hover:text-brass-bright">
            Leaderboard →
          </Link>
        </div>
        <p className="mt-1 font-body text-sm text-parchment-dim">
          Battles fought, models painted, and tales told — as approved by the inquisition.
        </p>
        <div className="mt-4">
          <ActivityFeed limit={15} />
        </div>
      </section>
    </main>
  );
}
