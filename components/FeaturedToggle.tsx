'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

export default function FeaturedToggle({
  playerAwardId,
  isFeatured,
}: {
  playerAwardId: string;
  isFeatured: boolean;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function onClick() {
    setError(null);
    startTransition(async () => {
      const supabase = createClient();
      const { error: err } = await supabase
        .from('player_awards')
        .update({ is_featured: !isFeatured })
        .eq('id', playerAwardId);
      if (err) {
        if (err.message.toLowerCase().includes('at most 3')) {
          setError('You can pin at most 3 awards — unpin one first.');
        } else {
          setError(err.message);
        }
        return;
      }
      router.refresh();
    });
  }

  return (
    <div>
      <button
        type="button"
        onClick={onClick}
        disabled={pending}
        className="w-full rounded border border-brass/40 bg-brass/10 px-2 py-1 text-[10px] font-display uppercase tracking-widest text-brass-bright transition-colors hover:border-brass hover:bg-brass/20 disabled:opacity-60"
      >
        {pending ? '…' : isFeatured ? 'Unpin from dashboard' : 'Pin to dashboard'}
      </button>
      {error && (
        <p className="mt-1 text-[10px] text-red-300">{error}</p>
      )}
    </div>
  );
}
