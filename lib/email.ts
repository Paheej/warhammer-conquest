import { Resend } from "resend";
import type { SupabaseClient } from "@supabase/supabase-js";

const resend = new Resend(process.env.RESEND_API_KEY);

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
  const to = await getAdminEmails(supabase);
  if (to.length === 0) {
    console.warn("sendAdminEmail: no admin emails found, skipping send");
    return;
  }

  await resend.emails.send({
    from: process.env.RESEND_FROM_EMAIL!,
    to,
    subject,
    html,
  });
}
