'use client';

// =====================================================================
// components/NavBar.tsx — REPLACEMENT for the existing NavBar.
// Mobile-friendly: hamburger menu collapses links on small screens.
// Preserves the grimdark parchment/brass aesthetic.
// =====================================================================

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { SignOutButton } from './SignOutButton';

interface NavLink {
  href: string;
  label: string;
  adminOnly?: boolean;
}

const LINKS: NavLink[] = [
  { href: '/',            label: 'Home' },
  { href: '/map',         label: 'Map' },
  { href: '/leaderboard', label: 'Leaderboard' },
  { href: '/submit',      label: 'Submit' },
  { href: '/dashboard',   label: 'Dashboard' },
  { href: '/admin',       label: 'Admin', adminOnly: true },
];

export function NavBar() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const [session, setSession] = useState<{ email: string | null; id: string | null } | null>(null);
  const [isAdmin, setIsAdmin] = useState(false);

  // Close mobile menu whenever route changes
  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  // Load auth + admin status (best-effort; doesn't block render)
  useEffect(() => {
    const supabase = createClient();
    let active = true;

    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!active) return;

      if (user) {
        setSession({ email: user.email ?? null, id: user.id });
        const { data: profile } = await supabase
          .from('profiles')
          .select('is_admin')
          .eq('id', user.id)
          .maybeSingle();
        if (active) setIsAdmin(Boolean(profile?.is_admin));
      } else {
        setSession(null);
        setIsAdmin(false);
      }
    })();

    const { data: listener } = supabase.auth.onAuthStateChange((_event, newSession) => {
      if (!active) return;
      setSession(newSession ? { email: newSession.user.email ?? null, id: newSession.user.id } : null);
    });

    return () => {
      active = false;
      listener.subscription.unsubscribe();
    };
  }, []);

  const visibleLinks = LINKS.filter((l) => !l.adminOnly || isAdmin);

  return (
    <header className="sticky top-0 z-40 border-b border-brass-700/50 bg-parchment-900/90 backdrop-blur-sm supports-[backdrop-filter]:bg-parchment-900/75">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-4 py-3 sm:px-6">
        {/* Brand */}
        <Link
          href="/"
          className="flex items-center gap-2 font-cinzel text-lg font-bold tracking-wide text-brass-100 sm:text-xl"
        >
          <span aria-hidden className="text-brass-400">✠</span>
          <span>Campaign Chronicle</span>
        </Link>

        {/* Desktop nav */}
        <nav className="hidden items-center gap-1 md:flex">
          {visibleLinks.map((link) => {
            const active = pathname === link.href || (link.href !== '/' && pathname.startsWith(link.href));
            return (
              <Link
                key={link.href}
                href={link.href}
                className={`rounded px-3 py-1.5 text-sm font-medium transition-colors ${
                  active
                    ? 'bg-brass-700/30 text-brass-100'
                    : 'text-parchment-200 hover:bg-brass-700/20 hover:text-brass-100'
                }`}
              >
                {link.label}
              </Link>
            );
          })}
          <div className="ml-2 flex items-center gap-2 border-l border-brass-700/40 pl-3">
            {session ? (
              <SignOutButton />
            ) : (
              <>
                <Link
                  href="/auth/login"
                  className="rounded px-3 py-1.5 text-sm text-parchment-200 hover:text-brass-100"
                >
                  Login
                </Link>
                <Link
                  href="/auth/signup"
                  className="rounded border border-brass-600 bg-brass-700/20 px-3 py-1.5 text-sm font-medium text-brass-100 hover:bg-brass-700/40"
                >
                  Sign up
                </Link>
              </>
            )}
          </div>
        </nav>

        {/* Mobile toggle */}
        <button
          type="button"
          className="inline-flex h-10 w-10 items-center justify-center rounded border border-brass-700/40 text-brass-100 md:hidden"
          aria-label={open ? 'Close menu' : 'Open menu'}
          aria-expanded={open}
          onClick={() => setOpen((v) => !v)}
        >
          {open ? (
            // X icon
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
              <path d="M6 6l12 12M6 18L18 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
            </svg>
          ) : (
            // Hamburger
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
              <path d="M4 7h16M4 12h16M4 17h16" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
            </svg>
          )}
        </button>
      </div>

      {/* Mobile sheet */}
      {open && (
        <div className="border-t border-brass-700/40 bg-parchment-900/95 md:hidden">
          <nav className="mx-auto flex max-w-6xl flex-col gap-1 px-4 py-3">
            {visibleLinks.map((link) => {
              const active = pathname === link.href || (link.href !== '/' && pathname.startsWith(link.href));
              return (
                <Link
                  key={link.href}
                  href={link.href}
                  className={`rounded px-3 py-2.5 text-base font-medium transition-colors ${
                    active
                      ? 'bg-brass-700/30 text-brass-100'
                      : 'text-parchment-200 hover:bg-brass-700/20 hover:text-brass-100'
                  }`}
                >
                  {link.label}
                </Link>
              );
            })}
            <div className="mt-2 border-t border-brass-700/30 pt-2">
              {session ? (
                <div className="flex items-center justify-between gap-2 px-3 py-2">
                  <span className="truncate text-sm text-parchment-300">{session.email}</span>
                  <SignOutButton />
                </div>
              ) : (
                <div className="flex items-center gap-2 px-3 py-2">
                  <Link
                    href="/auth/login"
                    className="flex-1 rounded border border-brass-700/40 px-3 py-2 text-center text-sm text-parchment-200"
                  >
                    Login
                  </Link>
                  <Link
                    href="/auth/signup"
                    className="flex-1 rounded border border-brass-600 bg-brass-700/20 px-3 py-2 text-center text-sm font-medium text-brass-100"
                  >
                    Sign up
                  </Link>
                </div>
              )}
            </div>
          </nav>
        </div>
      )}
    </header>
  );
}
