import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { SignOutButton } from "./SignOutButton";

export async function NavBar() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  let isAdmin = false;
  let displayName: string | null = null;
  if (user) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("display_name, is_admin")
      .eq("id", user.id)
      .single();
    isAdmin = profile?.is_admin ?? false;
    displayName = profile?.display_name ?? null;
  }

  return (
    <header className="border-b border-brass/20 bg-ink/80 backdrop-blur-md sticky top-0 z-50">
      <nav className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4 flex items-center justify-between">
        <Link href="/" className="flex items-center gap-3 group">
          <span className="text-3xl text-brass group-hover:text-brass-bright transition-colors">✠</span>
          <div>
            <div className="font-display text-lg tracking-widest text-parchment">
              CRUSADE LEDGER
            </div>
            <div className="font-body italic text-xs text-parchment-dark -mt-1">
              Campaign of the Burning Star
            </div>
          </div>
        </Link>

        <div className="flex items-center gap-1 md:gap-2">
          {user ? (
            <>
              <NavLink href="/map">Map</NavLink>
              <NavLink href="/leaderboard">Leaderboard</NavLink>
              <NavLink href="/submit">Submit</NavLink>
              <NavLink href="/dashboard">My Record</NavLink>
              {isAdmin && (
                <NavLink href="/admin" highlight>
                  Admin
                </NavLink>
              )}
              <div className="ml-2 hidden md:flex items-center gap-3 pl-4 border-l border-brass/20">
                <span className="text-sm text-parchment-dim font-body italic">
                  {displayName}
                </span>
                <SignOutButton />
              </div>
            </>
          ) : (
            <>
              <Link href="/auth/login" className="btn-ghost">
                Sign In
              </Link>
              <Link href="/auth/signup" className="btn-primary">
                Enlist
              </Link>
            </>
          )}
        </div>
      </nav>
    </header>
  );
}

function NavLink({
  href,
  children,
  highlight = false,
}: {
  href: string;
  children: React.ReactNode;
  highlight?: boolean;
}) {
  return (
    <Link
      href={href}
      className={`px-3 py-2 text-sm font-display uppercase tracking-wider transition-colors ${
        highlight
          ? "text-crusade hover:text-brass-bright"
          : "text-parchment-dim hover:text-parchment"
      }`}
    >
      {children}
    </Link>
  );
}
