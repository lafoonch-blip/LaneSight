import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabaseServer";

export const runtime = "nodejs";

export async function POST(req: Request) {
  const supabase = createClient();
  await supabase.auth.signOut(); // clears the session cookies
  return NextResponse.redirect(new URL("/login", req.url), { status: 303 });
}
