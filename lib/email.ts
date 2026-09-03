import { Resend } from "resend";
import type { SupabaseClient } from "@supabase/supabase-js";

export async function getAdminEmails(supabase: SupabaseClient): Promise<string[]> {
  const { data } = await supabase
    .from("profiles")
    .select("email")
    .eq("is_admin", true)
    .not("email", "is", null);
  return (data ?? []).map((row) => row.email as string).filter(Boolean);
}

export async function sendAdminEmail({
  supabase,
  subject,
  html,
}: {
  supabase: SupabaseClient;
  subject: string;
  html: string;
}) {
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.RESEND_FROM_EMAIL;
  if (!apiKey || !from) {
    console.warn("sendAdminEmail: RESEND_API_KEY/RESEND_FROM_EMAIL not configured, skipping send");
    return;
  }

  const to = await getAdminEmails(supabase);
  if (to.length === 0) {
    console.warn("sendAdminEmail: no admin emails found, skipping send");
    return;
  }

  const resend = new Resend(apiKey);
  await resend.emails.send({ from, to, subject, html });
}
