'use client';

import { useEffect, useRef } from 'react';
import { toast } from 'sonner';
import { createClient } from '@/lib/supabase/client';
import { AWARD_TIER_LABELS, type Award, type AwardTier } from '@/lib/types';

const TIER_ACCENT: Record<AwardTier, string> = {
  common:     'text-brass-bright',
  honoured:   'text-amber-200',
  legendary:  'text-purple-200',
  adamantium: 'text-red-200',
};

interface UnnotifiedRow {
  id: string;
  awards: Pick<Award, 'name' | 'icon' | 'tier'> | null;
}

export default function AwardToaster({ userId }: { userId: string }) {
  const ranRef = useRef(false);

  useEffect(() => {
    if (ranRef.current) return;
    ranRef.current = true;

    const supabase = createClient();

    (async () => {
      const { data, error } = await supabase
        .from('player_awards')
        .select('id, awards(name, icon, tier)')
        .eq('player_id', userId)
        .eq('notified', false)
        .order('earned_at', { ascending: true });

      if (error || !data || data.length === 0) return;

      const rows = data as unknown as UnnotifiedRow[];

      for (const row of rows) {
        if (!row.awards) continue;
        const tier = row.awards.tier;
        toast(
          <div className="flex items-center gap-3">
            <span className={`text-2xl ${TIER_ACCENT[tier]}`}>{row.awards.icon}</span>
            <div>
              <div className="font-display tracking-wider text-brass-bright">{row.awards.name}</div>
              <div className="text-[10px] uppercase tracking-widest text-parchment-dim">
                Honour Earned · {AWARD_TIER_LABELS[tier]}
              </div>
            </div>
          </div>,
          { duration: 7000 }
        );
      }

      const ids = rows.map((r) => r.id);
      await supabase
        .from('player_awards')
        .update({ notified: true })
        .in('id', ids);
    })();
  }, [userId]);

  return null;
}
