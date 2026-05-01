import type { Award, AwardTier, PlayerAward } from '@/lib/types';
import { AWARD_TIER_LABELS } from '@/lib/types';
import FeaturedToggle from './FeaturedToggle';

const TIER_CLASSES: Record<AwardTier, { card: string; tierBadge: string; icon: string }> = {
  common: {
    card: 'border-brass/40 bg-ink-2',
    tierBadge: 'border-brass/40 bg-brass/10 text-brass-bright',
    icon: 'text-brass-bright',
  },
  honoured: {
    card: 'border-amber-700/60 bg-ink-2',
    tierBadge: 'border-amber-700/60 bg-amber-900/30 text-amber-200',
    icon: 'text-amber-200',
  },
  legendary: {
    card: 'border-purple-700/60 bg-ink-2',
    tierBadge: 'border-purple-700/60 bg-purple-900/30 text-purple-200',
    icon: 'text-purple-200',
  },
  adamantium: {
    card: 'border-red-700/70 bg-ink-2 shadow-[0_0_12px_rgba(220,38,38,0.15)]',
    tierBadge: 'border-red-700/70 bg-red-900/40 text-red-200',
    icon: 'text-red-200',
  },
};

export interface AwardCardProps {
  award: Award;
  earned?: PlayerAward | null;
  progress?: { current: number; target: number } | null;
  showFeaturedToggle?: boolean;
}

export default function AwardCard({ award, earned, progress, showFeaturedToggle }: AwardCardProps) {
  const isEarned = !!earned;
  const isFeatured = !!earned?.is_featured;
  const tier = TIER_CLASSES[award.tier];

  if (isEarned) {
    return (
      <div
        className={`relative flex flex-col gap-2 rounded border p-3 ${tier.card} ${
          isFeatured ? 'ring-1 ring-brass/60' : ''
        }`}
      >
        {isFeatured && (
          <span className="absolute -top-2 left-3 rounded-full border border-brass/60 bg-ink px-2 py-0.5 text-[9px] font-display uppercase tracking-widest text-brass-bright">
            ★ Pinned
          </span>
        )}
        <div className="flex items-start gap-3">
          <span className={`text-3xl leading-none ${tier.icon}`}>{award.icon}</span>
          <div className="min-w-0 flex-1">
            <div className="font-display text-sm tracking-wider text-parchment">{award.name}</div>
            <div className="mt-0.5 text-xs text-parchment-dim">{award.description}</div>
          </div>
        </div>
        <div className="flex items-center justify-between gap-2">
          <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-display uppercase tracking-wider ${tier.tierBadge}`}>
            {AWARD_TIER_LABELS[award.tier]}
          </span>
          <span className="text-[10px] text-parchment-dark">
            Earned {new Date(earned!.earned_at).toLocaleDateString()}
          </span>
        </div>
        {showFeaturedToggle && earned && (
          <FeaturedToggle playerAwardId={earned.id} isFeatured={earned.is_featured} />
        )}
      </div>
    );
  }

  const inProgress = progress && progress.current > 0;
  const pct = progress ? Math.min(100, Math.round((progress.current / progress.target) * 100)) : 0;

  return (
    <div className="flex flex-col gap-2 rounded border border-dashed border-brass/20 bg-ink-2/60 p-3 opacity-80">
      <div className="flex items-start gap-3">
        <span className="text-3xl leading-none text-parchment-dark grayscale">{award.icon}</span>
        <div className="min-w-0 flex-1">
          <div className="font-display text-sm tracking-wider text-parchment-dim">
            {inProgress ? award.name : '???'}
          </div>
          <div className="mt-0.5 text-xs italic text-parchment-dark">{award.hint}</div>
        </div>
      </div>
      <div className="flex items-center justify-between gap-2">
        <span className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-display uppercase tracking-wider ${tier.tierBadge} opacity-50`}>
          {AWARD_TIER_LABELS[award.tier]}
        </span>
        {inProgress && (
          <span className="text-[10px] text-parchment-dim">
            {progress!.current} / {progress!.target}
          </span>
        )}
      </div>
      {inProgress && (
        <div className="h-1 w-full overflow-hidden rounded-full bg-brass/10">
          <div
            className="h-full bg-brass/60 transition-all"
            style={{ width: `${pct}%` }}
          />
        </div>
      )}
    </div>
  );
}
