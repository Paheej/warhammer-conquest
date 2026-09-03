import { createClient } from "@supabase/supabase-js";

/**
 * Service-role Supabase client for server-only routes (API routes, cron jobs).
 * Bypasses RLS — never import this from a client component.
 */
export function createAdminClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );
}
