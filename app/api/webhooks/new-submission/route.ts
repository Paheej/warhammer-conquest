import { NextResponse, type NextRequest } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { sendAdminEmail } from "@/lib/email";

const NOTIFICATION_KEY = "new_submission";
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

export async function POST(request: NextRequest) {
  const secret = request.headers.get("x-webhook-secret");
  if (!secret || secret !== process.env.SUPABASE_WEBHOOK_SECRET) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const supabase = createAdminClient();

  const { data: log } = await supabase
    .from("notification_log")
    .select("last_sent_at")
    .eq("key", NOTIFICATION_KEY)
    .maybeSingle();

  const lastSentAt = log?.last_sent_at ? new Date(log.last_sent_at).getTime() : null;
  if (lastSentAt && Date.now() - lastSentAt < ONE_DAY_MS) {
    return NextResponse.json({ skipped: "rate-limited" });
  }

  const { count } = await supabase
    .from("submissions")
    .select("id", { count: "exact", head: true })
    .eq("status", "pending");

  const pending = count ?? 0;
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "";

  await sendAdminEmail({
    supabase,
    subject: "New submission awaiting review",
    html: `
      <p>${pending} submission${pending === 1 ? " is" : "s are"} awaiting review in the Crusade admin queue.</p>
      <p><a href="${siteUrl}/admin">Open the admin queue</a></p>
    `,
  });

  await supabase
    .from("notification_log")
    .upsert({ key: NOTIFICATION_KEY, last_sent_at: new Date().toISOString() });

  return NextResponse.json({ sent: true, pending });
}
