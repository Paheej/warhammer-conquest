"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import type { Faction } from "@/lib/types";

export default function SignupPage() {
  const router = useRouter();
  const [factions, setFactions] = useState<Faction[]>([]);
  const [displayName, setDisplayName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [factionId, setFactionId] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    (async () => {
      const supabase = createClient();
      const { data } = await supabase
        .from("factions")
        .select("*")
        .order("name");
      setFactions((data as Faction[]) ?? []);
    })();
  }, []);

  async function handleSignup(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setInfo(null);
    setLoading(true);

    const supabase = createClient();
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
        data: { display_name: displayName },
      },
    });

    if (error) {
      setError(error.message);
      setLoading(false);
      return;
    }

    // If email confirmation is required, Supabase returns a user but no session.
    // If disabled, we also get a session and can proceed immediately.
    if (data.user && factionId) {
      await supabase
        .from("profiles")
        .update({ faction_id: factionId, display_name: displayName })
        .eq("id", data.user.id);
    }

    if (data.session) {
      router.push("/dashboard");
      router.refresh();
    } else {
      setInfo(
        "Check your email to confirm your account. Your faction choice is saved."
      );
      setLoading(false);
    }
  }

  async function handleDiscord() {
    setError(null);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "discord",
      options: {
        redirectTo: `${window.location.origin}/auth/callback?new=1`,
      },
    });
    if (error) setError(error.message);
  }

  return (
    <div className="max-w-lg mx-auto py-12 fade-up">
      <div className="text-center mb-8">
        <div className="text-brass text-4xl mb-3">✠</div>
        <h1 className="font-display text-3xl tracking-widest text-parchment">
          SWEAR THE OATH
        </h1>
        <p className="mt-2 font-body italic text-parchment-dim">
          Pledge your banner. Join the crusade.
        </p>
      </div>

      <div className="card p-8">
        <form onSubmit={handleSignup} className="space-y-4">
          <div>
            <label className="label">Commander's Name</label>
            <input
              type="text"
              required
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              className="input w-full"
              placeholder="Lord-Captain Varrus"
            />
          </div>

          <div>
            <label className="label">Vox Address</label>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="input w-full"
            />
          </div>

          <div>
            <label className="label">Cipher</label>
            <input
              type="password"
              required
              minLength={6}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="input w-full"
            />
          </div>

          <div>
            <label className="label">Chosen Faction</label>
            <select
              required
              value={factionId}
              onChange={(e) => setFactionId(e.target.value)}
              className="input w-full"
            >
              <option value="">— Select your banner —</option>
              {factions.map((f) => (
                <option key={f.id} value={f.id}>
                  {f.name}
                </option>
              ))}
            </select>
            <p className="mt-1 text-xs italic text-parchment-dark">
              You may change your banner later from your dashboard.
            </p>
          </div>

          {error && (
            <div className="text-sm text-crusade font-body border border-crusade/40 bg-crusade/10 p-3">
              {error}
            </div>
          )}
          {info && (
            <div className="text-sm text-brass font-body border border-brass/40 bg-brass/10 p-3">
              {info}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="btn-primary w-full disabled:opacity-50"
          >
            {loading ? "Inscribing…" : "Inscribe My Oath"}
          </button>
        </form>

        <div className="divider-ornate">
          <span>Or</span>
        </div>

        <button onClick={handleDiscord} className="btn-ghost w-full">
          Sign up with Discord
        </button>

        <p className="text-center mt-6 text-sm font-body italic text-parchment-dim">
          Already sworn in?{" "}
          <Link href="/auth/login" className="text-brass hover:text-brass-bright">
            Return to the ledger
          </Link>
        </p>
      </div>
    </div>
  );
}
