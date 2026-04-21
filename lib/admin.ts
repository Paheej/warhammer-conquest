/**
 * Returns true if the given email is listed in NEXT_PUBLIC_ADMIN_EMAILS.
 * This is used to *auto-promote* admins on first-sight, and as a quick client gate.
 * Real authorization is enforced by RLS policies + profile.is_admin on the database.
 */
export function isAdminEmail(email: string | null | undefined): boolean {
  if (!email) return false;
  const list = (process.env.NEXT_PUBLIC_ADMIN_EMAILS || "")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
  return list.includes(email.toLowerCase());
}
