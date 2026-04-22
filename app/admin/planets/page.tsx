// =====================================================================
// app/admin/planets/page.tsx
// New admin sub-page: lists every planet and renders the AdminPlanetEditor
// for each. Add a link to this from your existing /admin page.
//
// Access control relies on the existing admin pattern in your app —
// this page uses profiles.is_admin.
// =====================================================================

import { redirect } from 'next/navigation';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/server';
import AdminPlanetEditor from '@/components/AdminPlanetEditor';

export const dynamic = 'force-dynamic';

export default async function AdminPlanetsPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect('/auth/login?next=/admin/planets');

  const { data: profile } = await supabase
    .from('profiles')
    .select('is_admin')
    .eq('id', user.id)
    .maybeSingle();

  if (!profile?.is_admin) {
    return (
      <main className="mx-auto max-w-xl px-4 py-10 text-center text-parchment-200">
        <h1 className="font-cinzel text-2xl text-brass-100">Forbidden</h1>
        <p className="mt-2 text-sm">Only administrators may manage planets.</p>
        <Link href="/" className="mt-4 inline-block text-brass-300 hover:text-brass-100">← Home</Link>
      </main>
    );
  }

  const { data: planets } = await supabase
    .from('planets')
    .select('id, name, image_url, position_x, position_y, claim_threshold:threshold')
    .order('name');

  return (
    <main className="mx-auto max-w-5xl px-4 py-6 sm:px-6 sm:py-10">
      <header className="mb-6">
        <p className="font-cinzel text-xs uppercase tracking-[0.3em] text-brass-300">
          ✠ Admin ✠
        </p>
        <h1 className="mt-1 font-cinzel text-3xl text-brass-100">Planet Management</h1>
        <p className="mt-2 text-sm text-parchment-300">
          Set planet portraits and restrict which game editions may be played on each world.
        </p>
        <Link
          href="/admin"
          className="mt-3 inline-block text-sm text-brass-300 hover:text-brass-100"
        >
          ← Back to admin
        </Link>
      </header>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        {(planets ?? []).map((p) => (
          <AdminPlanetEditor key={p.id} planet={p} />
        ))}
      </div>
    </main>
  );
}
