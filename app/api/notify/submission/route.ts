import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { notifyAdmins } from "@/lib/admin-notify";

// Called by the submit forms right after a successful insert (issue #54).
// The 24h throttle is enforced in the DB, so repeated calls are harmless;
// we still require a signed-in player so randoms can't poke it.
export async function POST() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  try {
    const result = await notifyAdmins("new_submission");
    return NextResponse.json(result);
  } catch (err) {
    console.error("[notify/submission]", err);
    return NextResponse.json({ error: "notify_failed" }, { status: 500 });
  }
}
