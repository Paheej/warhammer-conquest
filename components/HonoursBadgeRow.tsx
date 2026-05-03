import type { Award, AwardTier, PlayerAward } from '@/lib/types';
import { AWARD_TIER_LABELS } from '@/lib/types';

const TIER_DOT: Record<AwardTier, string> = {
  common:     'border-brass/40 bg-ink',
  honoured:   'border-amber-700/60 bg-amber-900/20',
  legendary:  'border-purple-700/60 bg-purple-900/20',
  adamantium: 'border-red-700/70 bg-red-900/30',
};

export interface HonourBadge {
  player_award: Pick<PlayerAward, 'id' | 'is_featured'>;
  award: Pick<Award, 'name' | 'icon' | 'tier'>;
}

export default function HonoursBadgeRow({
  badges,
  max = 5,
  size = 'sm',
}: {
  badges: HonourBadge[];
  max?: number;
  size?: 'sm' | 'md';
}) {
  if (badges.length === 0) return null;

  const visible = badges.slice(0, max);
  const overflow = badges.length - visible.length;

  const dimension = size === 'md' ? 'h-8 w-8 text-base' : 'h-6 w-6 text-xs';

  return (
    <span className="inline-flex flex-wrap items-center gap-1 align-middle">
      {visible.map(({ player_award, award }) => (
        <span
          key={player_award.id}
          title={`${award.name} — ${AWARD_TIER_LABELS[award.tier]}${
            player_award.is_featured ? ' (Pinned)' : ''
          }`}
          className={`inline-flex ${dimension} items-center justify-center rounded-full border leading-none ${
            TIER_DOT[award.tier]
          } ${player_award.is_featured ? 'ring-1 ring-brass/60' : ''}`}
        >
          {award.icon}
        </span>
      ))}
      {overflow > 0 && (
        <span className="text-[10px] text-parchment-dim">+{overflow}</span>
      )}
    </span>
  );
}
