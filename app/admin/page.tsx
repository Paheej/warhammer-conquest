import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { AdminQueue } from "./AdminQueue";
import { AdminPlanets } from "./AdminPlanets";
import { AdminFactions } from "./AdminFactions";
import type { Submission, Faction, Planet, Profile } from "@/lib/types";

export const dynamic = "force-dynamic";

type PendingSubmission = Submission & {
  profiles: { display_name: string } | null;
};

export default async function AdminPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/auth/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .single();

  if (!profile || !(profile as Profile).is_admin) {
    redirect("/dashboard");
  }

  const [
    { data: pending },
    { data: planets },
    { data: factions },
  ] = await Promise.all([
    supabase
      .from("submissions")
      .select("*, profiles(display_name)")
      .eq("status", "pending")
      .order("created_at", { ascending: true }),
    supabase.from("planets").select("*").order("name"),
    supabase.from("factions").select("*").order("name"),
  ]);

  return (
    <div className="space-y-12 fade-up">
      <div className="text-center">
        <div className="text-crusade text-4xl mb-2">⚔</div>
        <h1 className="font-display text-4xl tracking-widest text-parchment">
          THE INQUISITION
        </h1>
        <p className="mt-2 font-body italic text-parchment-dim">
          Judgement is yours. Approve what is true, reject what is not.
        </p>
      </div>

      <section>
        <h2 className="font-display text-2xl tracking-widest text-parchment mb-4">
          APPROVAL QUEUE
          {pending && pending.length > 0 && (
            <span className="ml-3 text-crusade">({pending.length})</span>
          )}
        </h2>
        <AdminQueue
          submissions={(pending ?? []) as PendingSubmission[]}
          planets={(planets ?? []) as Planet[]}
          factions={(factions ?? []) as Faction[]}
        />
      </section>

      <section>
        <h2 className="font-display text-2xl tracking-widest text-parchment mb-4">
          WORLDS
        </h2>
        <AdminPlanets
          planets={(planets ?? []) as Planet[]}
          factions={(factions ?? []) as Faction[]}
        />
      </section>

      <section>
        <h2 className="font-display text-2xl tracking-widest text-parchment mb-4">
          FACTIONS
        </h2>
        <AdminFactions factions={(factions ?? []) as Faction[]} />
      </section>
    </div>
  );
}
