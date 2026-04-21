import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { isAdminEmail } from "@/lib/admin";

export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const isNew = searchParams.get("new") === "1";

  if (!code) {
    return NextResponse.redirect(`${origin}/auth/login?error=missing_code`);
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    return NextResponse.redirect(`${origin}/auth/login?error=${encodeURIComponent(error.message)}`);
  }

  // Promote admins by email, if applicable
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user?.email && isAdminEmail(user.email)) {
    await supabase
      .from("profiles")
      .update({ is_admin: true })
      .eq("id", user.id);
  }

  return NextResponse.redirect(`${origin}${isNew ? "/dashboard?welcome=1" : "/dashboard"}`);
}
