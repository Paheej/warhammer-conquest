import { NextResponse, type NextRequest } from "next/server";
import { notifyAdmins } from "@/lib/admin-notify";

// Sunday reminder to admins if anything is still pending (issue #54).
// Scheduled in vercel.json. Vercel sends `Authorization: Bearer $CRON_SECRET`.
export async function GET(request: NextRequest) {
  const secret = process.env.CRON_SECRET;
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  try {
    const result = await notifyAdmins("weekly_digest");
    return NextResponse.json(result);
  } catch (err) {
    console.error("[cron/weekly-digest]", err);
    return NextResponse.json({ error: "notify_failed" }, { status: 500 });
  }
}
