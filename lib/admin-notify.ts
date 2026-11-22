// =====================================================================
// lib/admin-notify.ts
// Issue #54: emails admins about submissions awaiting approval.
//   new_submission — fired by /api/notify/submission, max once per 24h
//   weekly_digest  — fired by the Sunday Vercel cron
// Throttling lives in the DB (claim_admin_notification, 0019) so it holds
// across serverless instances. Server-only.
// =====================================================================

import { createServiceClient } from "@/lib/supabase/service";
import { sendEmail } from "@/lib/email";
import type { SubmissionType } from "@/lib/types";

export type NotificationKind = "new_submission" | "weekly_digest";

const MIN_INTERVAL: Record<NotificationKind, string> = {
  new_submission: "24 hours",
  // Cron fires weekly; the 6-day guard only stops a retried/duplicate run
  // from sending twice.
  weekly_digest: "6 days",
};

const TYPE_LABEL: Record<SubmissionType, string> = {
  game: "Battle",
  model: "Painted model",
  scribe: "Scribe",
  loremaster: "Loremaster",
  bonus: "Bonus",
};

const LIST_LIMIT = 15;

export type NotifyResult =
  | { sent: true; recipients: number; pending: number }
  | { sent: false; reason: "nothing_pending" | "throttled" | "no_admins" };

interface PendingRow {
  id: string;
  type: SubmissionType;
  title: string | null;
  created_at: string;
  player: { display_name: string } | null;
}

function appUrl(): string {
  return (process.env.APP_URL || "https://www.campaign-chronicle.app").replace(/\/$/, "");
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function formatWhen(iso: string): string {
  return new Date(iso).toLocaleString("en-US", {
    timeZone: "America/New_York",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

async function getAdminEmails(
  supabase: ReturnType<typeof createServiceClient>,
): Promise<string[]> {
  const { data, error } = await supabase
    .from("profiles")
    .select("email")
    .eq("is_admin", true)
    .not("email", "is", null);
  if (error) throw new Error(`Loading admins failed: ${error.message}`);

  const fromEnv = (process.env.NEXT_PUBLIC_ADMIN_EMAILS || "").split(",");
  const all = [...(data ?? []).map((r) => r.email as string), ...fromEnv]
    .map((e) => e.trim().toLowerCase())
    .filter((e) => e.includes("@") && !e.startsWith("replace_with"));
  return Array.from(new Set(all));
}

function buildEmail(kind: NotificationKind, pending: number, rows: PendingRow[]) {
  const queueUrl = `${appUrl()}/admin`;
  const noun = pending === 1 ? "submission" : "submissions";
  const subject =
    kind === "weekly_digest"
      ? `Weekly reminder: ${pending} ${noun} awaiting approval`
      : `New ${noun} awaiting approval (${pending} pending)`;
  const intro =
    kind === "weekly_digest"
      ? `There ${pending === 1 ? "is" : "are"} still ${pending} ${noun} waiting in the admin queue.`
      : `A player just submitted a deed. There ${pending === 1 ? "is" : "are"} ${pending} ${noun} waiting in the admin queue.`;
  const more = pending > rows.length ? pending - rows.length : 0;

  const lines = rows.map((r) => {
    const who = r.player?.display_name ?? "Unknown player";
    const title = r.title?.trim() || "(untitled)";
    return { who, title, label: TYPE_LABEL[r.type] ?? r.type, when: formatWhen(r.created_at) };
  });

  const text = [
    intro,
    "",
    ...lines.map((l) => `- ${l.label}: ${l.title} — ${l.who} (${l.when})`),
    ...(more ? [`…and ${more} more`] : []),
    "",
    `Review them: ${queueUrl}`,
    "",
    kind === "new_submission"
      ? "You'll get at most one of these per day, plus a Sunday reminder if anything is still pending."
      : "You'll get this reminder every Sunday while anything is pending.",
  ].join("\n");

  const html = `
<div style="font-family:Georgia,serif;max-width:560px;color:#1a1a1a">
  <h2 style="margin:0 0 12px">Campaign Chronicle</h2>
  <p>${escapeHtml(intro)}</p>
  <ul style="padding-left:20px">
    ${lines
      .map(
        (l) =>
          `<li style="margin-bottom:6px"><strong>${escapeHtml(l.label)}:</strong> ${escapeHtml(l.title)} — ${escapeHtml(l.who)} <span style="color:#666">(${escapeHtml(l.when)})</span></li>`,
      )
      .join("\n    ")}
    ${more ? `<li style="color:#666">…and ${more} more</li>` : ""}
  </ul>
  <p><a href="${queueUrl}" style="display:inline-block;background:#3c8dbc;color:#fff;padding:10px 16px;border-radius:4px;text-decoration:none">Open the admin queue</a></p>
  <p style="color:#666;font-size:12px">${
    kind === "new_submission"
      ? "You'll get at most one of these per day, plus a Sunday reminder if anything is still pending."
      : "You'll get this reminder every Sunday while anything is pending."
  }</p>
</div>`.trim();

  return { subject, html, text };
}

export async function notifyAdmins(kind: NotificationKind): Promise<NotifyResult> {
  const supabase = createServiceClient();

  // Real pending items only — mirror rows are created on approval, but be safe.
  const { data, count, error } = await supabase
    .from("submissions")
    .select("id, type, title, created_at, player:profiles!submissions_player_id_fkey(display_name)", {
      count: "exact",
    })
    .eq("status", "pending")
    .is("mirror_of", null)
    .order("created_at", { ascending: false })
    .limit(LIST_LIMIT);
  if (error) throw new Error(`Loading pending submissions failed: ${error.message}`);

  const pending = count ?? 0;
  if (pending === 0) return { sent: false, reason: "nothing_pending" };

  const recipients = await getAdminEmails(supabase);
  if (recipients.length === 0) return { sent: false, reason: "no_admins" };

  const { data: claim, error: claimErr } = await supabase
    .rpc("claim_admin_notification", {
      p_kind: kind,
      p_min_interval: MIN_INTERVAL[kind],
    })
    .single<{ claimed: boolean; previous: string | null }>();
  if (claimErr || !claim) throw new Error(`Claim failed: ${claimErr?.message ?? "no row"}`);
  if (!claim.claimed) return { sent: false, reason: "throttled" };

  const email = buildEmail(kind, pending, (data ?? []) as unknown as PendingRow[]);
  try {
    await sendEmail({ to: recipients, ...email });
  } catch (err) {
    // Give the window back so the next submission retries.
    await supabase.rpc("release_admin_notification", {
      p_kind: kind,
      p_previous: claim.previous,
    });
    throw err;
  }

  return { sent: true, recipients: recipients.length, pending };
}
