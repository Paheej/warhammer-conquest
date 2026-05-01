import type { Award, AwardTier, PlayerAward } from '@/lib/types';
import { AWARD_TIER_LABELS } from '@/lib/types';

const TIER_GLOW: Record<AwardTier, string> = {
  common:     'border-brass/50 bg-ink-2',
  honoured:   'border-amber-700/70 bg-ink-2',
  legendary:  'border-purple-700/70 bg-ink-2',
  adamantium: 'border-red-700/80 bg-ink-2 shadow-[0_0_18px_rgba(220,38,38,0.2)]',
};

export interface FeaturedAward {
  player_award: PlayerAward;
  award: Award;
}

export default function HonoursStrip({ featured }: { featured: FeaturedAward[] }) {
  if (featured.length === 0) return null;

  return (
    <section className="card p-4 mt-6">
      <div className="font-display uppercase tracking-widest text-xs text-brass mb-3">
        ✠ Pinned Honours ✠
      </div>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        {featured.map(({ player_award, award }) => (
          <div
            key={player_award.id}
            className={`flex items-center gap-3 rounded border p-3 ${TIER_GLOW[award.tier]}`}
          >
            <span className="text-4xl leading-none">{award.icon}</span>
            <div className="min-w-0 flex-1">
              <div className="font-display text-sm tracking-wider text-brass-bright truncate">
                {award.name}
              </div>
              <div className="text-[10px] uppercase tracking-widest text-parchment-dim">
                {AWARD_TIER_LABELS[award.tier]}
              </div>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
