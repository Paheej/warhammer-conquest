// =====================================================================
// components/ActivityFeed.tsx
// Server component — fetches approved submissions from the activity_feed
// view and renders them. Drop this onto app/page.tsx (the Home page).
// =====================================================================

import Link from 'next/link';
import Image from 'next/image';
import { createServerClient } from '@/lib/supabase/server';
import type { ActivityFeedItem } from '@/lib/types';

function timeAgo(iso: string): string {
  const d = new Date(iso);
  const diff = Date.now() - d.getTime();
  const sec = Math.floor(diff / 1000);
  if (sec < 60)     return `${sec}s ago`;
  const min = Math.floor(sec / 60);
  if (min < 60)     return `${min}m ago`;
  const hr  = Math.floor(min / 60);
  if (hr  < 24)     return `${hr}h ago`;
  const day = Math.floor(hr / 24);
  if (day < 30)     return `${day}d ago`;
  const mo  = Math.floor(day / 30);
  if (mo  < 12)     return `${mo}mo ago`;
  const yr  = Math.floor(mo / 12);
  return `${yr}y ago`;
}

function KindBadge({ kind }: { kind: string }) {
  const map: Record<string, { label: string; cls: string; icon: string }> = {
    battle:  { label: 'Battle',  cls: 'border-red-700/60   bg-red-900/30   text-red-200',    icon: '⚔' },
    painted: { label: 'Painted', cls: 'border-blue-700/60  bg-blue-900/30  text-blue-200',   icon: '🖌' },
    lore:    { label: 'Lore',    cls: 'border-amber-700/60 bg-amber-900/30 text-amber-200',  icon: '📜' },
    bonus:   { label: 'Bonus',   cls: 'border-purple-700/60 bg-purple-900/30 text-purple-200', icon: '✦' },
  };
  const cfg = map[kind] ?? { label: kind, cls: 'border-brass-700/60 bg-brass-900/30 text-brass-200', icon: '✠' };
  return (
    <span className={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-medium ${cfg.cls}`}>
      <span aria-hidden>{cfg.icon}</span> {cfg.label}
    </span>
  );
}

function ResultBadge({ result }: { result: string | null }) {
  if (!result) return null;
  const map: Record<string, string> = {
    win:  'border-green-700/60 bg-green-900/30 text-green-200',
    loss: 'border-red-700/60   bg-red-900/30   text-red-200',
    draw: 'border-yellow-700/60 bg-yellow-900/30 text-yellow-200',
  };
  return (
    <span className={`inline-flex rounded border px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider ${map[result] ?? ''}`}>
      {result}
    </span>
  );
}

export default async function ActivityFeed({ limit = 15 }: { limit?: number }) {
  const supabase = await createServerClient();

  const { data, error } = await supabase
    .from('activity_feed')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(limit);

  if (error) {
    return (
      <div className="rounded border border-brass-700/40 bg-parchment-900/40 p-4 text-sm text-parchment-300">
        Unable to load the activity feed right now.
      </div>
    );
  }

  const items = (data ?? []) as ActivityFeedItem[];

  if (items.length === 0) {
    return (
      <div className="rounded border border-brass-700/40 bg-parchment-900/40 p-6 text-center text-parchment-300">
        <p className="font-cinzel text-lg text-brass-200">The archives are silent.</p>
        <p className="mt-1 text-sm">No deeds have been chronicled yet. Be the first to make history.</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      {items.map((it) => (
        <article
          key={it.submission_id}
          className="group flex flex-col gap-3 rounded border border-brass-700/40 bg-parchment-900/50 p-4 transition-colors hover:border-brass-600 sm:flex-row"
        >
          {/* Avatar / image */}
          <div className="flex shrink-0 items-start gap-3 sm:flex-col sm:items-center">
            <Link
              href={it.user_id ? `/player/${it.user_id}` : '#'}
              className="block h-12 w-12 shrink-0 overflow-hidden rounded-full border border-brass-700/50 bg-parchment-800"
            >
              {it.avatar_url ? (
                // Using <img> rather than next/image so external URLs don't need next.config.js tweaks.
                // eslint-disable-next-line @next/next/no-img-element
                <img src={it.avatar_url} alt={it.display_name} className="h-full w-full object-cover" />
              ) : (
                <div className="flex h-full w-full items-center justify-center font-cinzel text-brass-300">
                  {it.display_name.charAt(0).toUpperCase()}
                </div>
              )}
            </Link>
          </div>

          <div className="flex min-w-0 flex-1 flex-col gap-2">
            {/* Header row */}
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <Link
                href={it.user_id ? `/player/${it.user_id}` : '#'}
                className="font-cinzel text-brass-100 hover:text-brass-300"
              >
                {it.display_name}
              </Link>
              {it.faction_name && (
                <span
                  className="rounded px-1.5 py-0.5 text-xs font-medium text-parchment-100"
                  style={{ backgroundColor: it.faction_color ?? '#7a5b20' }}
                >
                  {it.faction_name}
                </span>
              )}
              <KindBadge kind={it.kind} />
              {it.result && <ResultBadge result={it.result} />}
              {it.game_system_short && (
                <span className="rounded border border-brass-700/40 px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-brass-300">
                  {it.game_system_short}
                </span>
              )}
              <span className="ml-auto shrink-0 text-xs text-parchment-400">{timeAgo(it.created_at)}</span>
            </div>

            {/* Title / description */}
            {it.title && (
              <p className="font-cinzel text-base text-parchment-100">{it.title}</p>
            )}
            {it.description && (
              <p className="line-clamp-3 text-sm text-parchment-200">{it.description}</p>
            )}

            {/* Metadata row */}
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-parchment-300">
              {it.planet_name && (
                <span>
                  <span className="text-brass-400">◈</span>{' '}
                  <Link href={`/map?planet=${it.planet_id}`} className="hover:text-brass-200">
                    {it.planet_name}
                  </Link>
                </span>
              )}
              {it.adversary_name && (
                <span>
                  vs{' '}
                  <Link
                    href={it.adversary_user_id ? `/player/${it.adversary_user_id}` : '#'}
                    className="text-brass-200 hover:text-brass-100"
                  >
                    {it.adversary_name}
                  </Link>
                  {it.adversary_faction_name && (
                    <span className="text-parchment-400"> ({it.adversary_faction_name})</span>
                  )}
                </span>
              )}
              {it.video_game_name && (
                <span className="text-parchment-400">🎮 {it.video_game_name}</span>
              )}
              {it.game_size && it.game_size !== 'n/a' && (
                <span className="capitalize text-parchment-400">{it.game_size} battle</span>
              )}
              {it.points !== null && it.points > 0 && (
                <span className="text-brass-300">+{it.points} glory</span>
              )}
            </div>

            {/* Image */}
            {it.image_url && (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={it.image_url}
                alt={it.title ?? 'Submission'}
                className="mt-1 max-h-80 w-full rounded border border-brass-700/30 object-cover"
                loading="lazy"
              />
            )}
          </div>
        </article>
      ))}
    </div>
  );
}
