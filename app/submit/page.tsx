import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SubmitForm } from "./SubmitForm";
import type { Faction, Planet, Profile } from "@/lib/types";

export const dynamic = "force-dynamic";

export default async function SubmitPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/auth/login");

  const [{ data: profile }, { data: factions }, { data: planets }] = await Promise.all([
    supabase.from("profiles").select("*").eq("id", user.id).single(),
    supabase.from("factions").select("*").order("name"),
    supabase.from("planets").select("*").order("name"),
  ]);

  return (
    <div className="max-w-3xl mx-auto fade-up">
      <div className="text-center mb-8">
        <div className="text-brass text-3xl mb-2">✠</div>
        <h1 className="font-display text-4xl tracking-widest text-parchment">
          LOG A DEED
        </h1>
        <p className="mt-2 font-body italic text-parchment-dim">
          All submissions are reviewed by the Inquisition before glory is awarded.
        </p>
      </div>

      <SubmitForm
        profile={profile as Profile}
        factions={(factions ?? []) as Faction[]}
        planets={(planets ?? []) as Planet[]}
      />
    </div>
  );
}
