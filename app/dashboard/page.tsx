import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { DashboardProfile } from "./DashboardProfile";
import type { Faction, Profile, Submission } from "@/lib/types";

export const dynamic = "force-dynamic";

export default async function DashboardPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/auth/login");

  const [{ data: profile }, { data: factions }, { data: submissions }] = await Promise.all([
    supabase.from("profiles").select("*").eq("id", user.id).single(),
    supabase.from("factions").select("*").order("name"),
    supabase
      .from("submissions")
      .select("*")
      .eq("player_id", user.id)
      .order("created_at", { ascending: false }),
  ]);

  const p = profile as Profile;
  const subs = (submissions ?? []) as Submission[];
  const pending = subs.filter((s) => s.status === "pending");
  const approved = subs.filter((s) => s.status === "approved");
  const rejected = subs.filter((s) => s.status === "rejected");
  const totalGlory = approved.reduce((sum, s) => sum + s.points, 0);
  const myFaction = p.faction_id
    ? (factions ?? []).find((f) => f.id === p.faction_id)
    : null;

  return (
    <div className="space-y-8 fade-up">
      <div className="text-center">
        <div className="text-brass text-3xl mb-2">✠</div>
        <h1 className="font-display text-4xl tracking-widest text-parchment">
          {p.display_name.toUpperCase()}
        </h1>
        {myFaction && (
          <p className="mt-2 font-body italic" style={{ color: myFaction.color }}>
            Of the {myFaction.name}
          </p>
        )}
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard label="Glory Earned" value={totalGlory} emphasis />
        <StatCard label="Approved" value={approved.length} />
        <StatCard label="Pending" value={pending.length} pendingIfAny />
        <StatCard label="Rejected" value={rejected.length} />
      </div>

      {/* Profile editor */}
      <DashboardProfile profile={p} factions={(factions ?? []) as Faction[]} />

      {/* Recent submissions */}
      <section>
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-display text-xl tracking-widest text-parchment">
            YOUR DEEDS
          </h2>
          <Link href="/submit" className="btn-ghost">
            Log Another
          </Link>
        </div>
        {subs.length === 0 ? (
          <div className="card p-10 text-center text-parchment-dim italic">
            No deeds recorded. The ledger awaits your first entry.
          </div>
        ) : (
          <div className="space-y-3">
            {subs.map((s) => (
              <div key={s.id} className="card p-4">
                <div className="flex items-start justify-between gap-4">
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <span className="text-xs font-display uppercase tracking-widest text-brass px-2 py-0.5 border border-brass/30">
                        {s.type}
                      </span>
                      <StatusBadge status={s.status} />
                    </div>
                    <div className="font-display text-lg text-parchment">{s.title}</div>
                    {s.review_notes && (
                      <div className="mt-2 text-sm italic text-parchment-dim">
                        Inquisitor's note: {s.review_notes}
                      </div>
                    )}
                  </div>
                  <div className="text-right shrink-0">
                    <div className="font-display text-xl text-brass-bright">{s.points}</div>
                    <div className="text-xs uppercase tracking-wider text-parchment-dark">pts</div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function StatCard({
  label,
  value,
  emphasis = false,
  pendingIfAny = false,
}: {
  label: string;
  value: number;
  emphasis?: boolean;
  pendingIfAny?: boolean;
}) {
  const color = emphasis
    ? "text-brass-bright"
    : pendingIfAny && value > 0
    ? "text-crusade"
    : "text-parchment";
  return (
    <div className="card p-5 text-center">
      <div className={`font-display text-3xl ${color}`}>{value}</div>
      <div className="mt-1 text-xs font-display uppercase tracking-widest text-parchment-dark">
        {label}
      </div>
    </div>
  );
}

function StatusBadge({ status }: { status: Submission["status"] }) {
  const map = {
    pending: { label: "Awaiting Judgement", cls: "border-parchment-dark/40 text-parchment-dark" },
    approved: { label: "Sealed", cls: "border-brass-bright/60 text-brass-bright" },
    rejected: { label: "Rejected", cls: "border-crusade/60 text-crusade" },
  } as const;
  const { label, cls } = map[status];
  return (
    <span className={`text-xs font-display uppercase tracking-widest px-2 py-0.5 border ${cls}`}>
      {label}
    </span>
  );
}
