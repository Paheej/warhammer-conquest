import { NextResponse, type NextRequest } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { sendAdminEmail } from "@/lib/email";

const NOTIFICATION_KEY = "weekly_digest";

export async function GET(request: NextRequest) {
  const auth = request.headers.get("authorization");
  if (auth !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const supabase = createAdminClient();

  const { count } = await supabase
    .from("submissions")
    .select("id", { count: "exact", head: true })
    .eq("status", "pending");

  const pending = count ?? 0;
  if (pending === 0) {
    return NextResponse.json({ skipped: "queue empty" });
  }

  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "";

  await sendAdminEmail({
    supabase,
    subject: `Weekly digest: ${pending} submission${pending === 1 ? "" : "s"} awaiting review`,
    html: `
      <p>${pending} submission${pending === 1 ? " is" : "s are"} still waiting in the Crusade admin queue.</p>
      <p><a href="${siteUrl}/admin">Open the admin queue</a></p>
    `,
  });

  await supabase
    .from("notification_log")
    .upsert({ key: NOTIFICATION_KEY, last_sent_at: new Date().toISOString() });

  return NextResponse.json({ sent: true, pending });
}
