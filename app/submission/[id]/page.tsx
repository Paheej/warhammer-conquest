// =====================================================================
// app/submission/[id]/page.tsx
// Public detail page for a single approved deed. Shows full title,
// untruncated description, full-size uncropped image, and all the
// metadata that the activity feed card only previews.
//
// Queries from activity_feed, which already filters status='approved',
// so unapproved submissions 404 rather than leak.
// =====================================================================

import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import type { ActivityFeedItem } from '@/lib/types';

export const dynamic = 'force-dynamic';

interface PageProps {
  params: Promise<{ id: string }>;
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, {
    year: 'numeric', month: 'long', day: 'numeric',
  });
}

const KIND_LABELS: Record<string, { label: string; icon: string }> = {
  battle:  { label: 'Battle Report', icon: '⚔' },
  painted: { label: 'Painted',       icon: '🖌' },
  lore:    { label: 'Lore',          icon: '📜' },
  bonus:   { label: 'Bonus',         icon: '✦' },
};

export default async function SubmissionDetailPage({ params }: PageProps) {
  const { id } = await params;
  const supabase = await createClient();

  const { data } = await supabase
    .from('activity_feed')
    .select('*')
    .eq('submission_id', id)
    .maybeSingle();

  if (!data) notFound();
  const it = data as ActivityFeedItem;

  const kindMeta = KIND_LABELS[it.kind] ?? { label: it.kind, icon: '✠' };

  return (
    <main className="mx-auto max-w-3xl px-4 py-8 sm:px-6 sm:py-12">
      {/* Breadcrumb / back link */}
      <Link
        href="/"
        className="inline-flex items-center gap-1 text-sm text-parchment-dim hover:text-brass-bright transition-colors"
      >
        ← Back to the chronicle
      </Link>

      <article className="mt-6 card p-6 sm:p-8">
        {/* Header: kind, faction, date */}
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="inline-flex items-center gap-1 rounded-full border border-brass/40 bg-brass/10 px-2 py-0.5 text-xs font-display uppercase tracking-wider text-brass-bright">
            <span aria-hidden>{kindMeta.icon}</span> {kindMeta.label}
          </span>
          {it.result && (
            <span
              className={`rounded border px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider ${
                it.result === 'win'
                  ? 'border-green-700/60 bg-green-900/30 text-green-200'
                  : it.result === 'loss'
                  ? 'border-red-700/60 bg-red-900/30 text-red-200'
                  : 'border-yellow-700/60 bg-yellow-900/30 text-yellow-200'
              }`}
            >
              {it.result}
            </span>
          )}
          {it.faction_name && (
            <span
              className="rounded px-1.5 py-0.5 text-xs font-medium text-parchment"
              style={{ backgroundColor: it.faction_color ?? '#7a5b20' }}
            >
              {it.faction_name}
            </span>
          )}
          <span className="ml-auto text-xs text-parchment-dark">
            {formatDate(it.created_at)}
          </span>
        </div>

        {/* Title */}
        {it.title && (
          <h1 className="mt-4 font-display text-3xl tracking-wider text-parchment">
            {it.title}
          </h1>
        )}

        {/* Byline */}
        <div className="mt-3 flex flex-wrap items-center gap-2 text-sm text-parchment-dim">
          <span>by</span>
          {it.user_id ? (
            <Link
              href={`/player/${it.user_id}`}
              className="font-display text-parchment hover:text-brass-bright transition-colors"
            >
              {it.display_name}
            </Link>
          ) : (
            <span className="font-display text-parchment">{it.display_name}</span>
          )}
        </div>

        {/* Full-size image — object-contain so nothing gets cropped. */}
        {it.image_url && (
          <div className="mt-6 overflow-hidden rounded border border-brass/30 bg-ink">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={it.image_url}
              alt={it.title ?? 'Submission image'}
              className="mx-auto block max-h-[70vh] w-auto object-contain"
            />
          </div>
        )}

        {/* Description / lore body */}
        {it.description && (
          <div className="mt-6 whitespace-pre-wrap font-body text-base leading-relaxed text-parchment">
            {it.description}
          </div>
        )}

        {/* Metadata panel */}
        <dl className="mt-8 grid grid-cols-1 gap-x-6 gap-y-3 border-t border-brass/20 pt-6 text-sm sm:grid-cols-2">
          {it.planet_name && (
            <div>
              <dt className="label">World</dt>
              <dd className="mt-0.5">
                <Link
                  href={`/map?planet=${it.planet_id}`}
                  className="text-parchment hover:text-brass-bright transition-colors"
                >
                  ◈ {it.planet_name}
                </Link>
              </dd>
            </div>
          )}
          {it.adversary_name && (
            <div>
              <dt className="label">Adversary</dt>
              <dd className="mt-0.5">
                {it.adversary_user_id ? (
                  <Link
                    href={`/player/${it.adversary_user_id}`}
                    className="text-parchment hover:text-brass-bright transition-colors"
                  >
                    {it.adversary_name}
                  </Link>
                ) : (
                  <span className="text-parchment">{it.adversary_name}</span>
                )}
                {it.adversary_faction_name && (
                  <span className="text-parchment-dim"> · {it.adversary_faction_name}</span>
                )}
              </dd>
            </div>
          )}
          {it.game_system_name && (
            <div>
              <dt className="label">Game System</dt>
              <dd className="mt-0.5 text-parchment">{it.game_system_name}</dd>
            </div>
          )}
          {it.video_game_name && (
            <div>
              <dt className="label">Video Game</dt>
              <dd className="mt-0.5 text-parchment">🎮 {it.video_game_name}</dd>
            </div>
          )}
          {it.game_size && it.game_size !== 'n/a' && (
            <div>
              <dt className="label">Battle Size</dt>
              <dd className="mt-0.5 capitalize text-parchment">{it.game_size}</dd>
            </div>
          )}
          {it.points !== null && it.points > 0 && (
            <div>
              <dt className="label">Glory Earned</dt>
              <dd className="mt-0.5 font-display text-brass-bright">+{it.points}</dd>
            </div>
          )}
        </dl>
      </article>
    </main>
  );
}
