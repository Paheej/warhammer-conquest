"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleEmailLogin(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      setError(error.message);
      setLoading(false);
      return;
    }
    router.push("/dashboard");
    router.refresh();
  }

  async function handleDiscordLogin() {
    setError(null);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "discord",
      options: {
        redirectTo: `${window.location.origin}/auth/callback`,
      },
    });
    if (error) setError(error.message);
  }

  return (
    <div className="max-w-md mx-auto py-12 fade-up">
      <div className="text-center mb-8">
        <div className="text-brass text-4xl mb-3">✠</div>
        <h1 className="font-display text-3xl tracking-widest text-parchment">
          RETURN TO THE LEDGER
        </h1>
        <p className="mt-2 font-body italic text-parchment-dim">
          The Emperor remembers those who serve.
        </p>
      </div>

      <div className="card p-8">
        <form onSubmit={handleEmailLogin} className="space-y-4">
          <div>
            <label className="label">Vox Address</label>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="input w-full"
              placeholder="commander@imperium.gov"
            />
          </div>
          <div>
            <label className="label">Cipher</label>
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="input w-full"
            />
          </div>

          {error && (
            <div className="text-sm text-crusade font-body border border-crusade/40 bg-crusade/10 p-3">
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="btn-primary w-full disabled:opacity-50"
          >
            {loading ? "Authenticating…" : "Enter the Crusade"}
          </button>
        </form>

        <div className="divider-ornate">
          <span>Or</span>
        </div>

        <button onClick={handleDiscordLogin} className="btn-ghost w-full">
          Sign in with Discord
        </button>

        <p className="text-center mt-6 text-sm font-body italic text-parchment-dim">
          No record of your service?{" "}
          <Link href="/auth/signup" className="text-brass hover:text-brass-bright">
            Enlist now
          </Link>
        </p>
      </div>
    </div>
  );
}
