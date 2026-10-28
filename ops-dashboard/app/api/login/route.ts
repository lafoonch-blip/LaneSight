import { NextResponse } from "next/server";
import { COOKIE_NAME, authConfigured, mintSession, verifyToken } from "@/lib/auth";

export const runtime = "nodejs";

export async function POST(req: Request) {
  if (!authConfigured()) {
    // Fail closed: no owner token configured -> refuse, never open the dashboard.
    return NextResponse.json({ error: "owner auth not configured" }, { status: 503 });
  }
  const form = await req.formData();
  const token = String(form.get("token") ?? "");
  const next = String(form.get("next") ?? "/");
  if (!verifyToken(token)) {
    const url = new URL("/login", req.url);
    url.searchParams.set("error", "1");
    if (next && next !== "/") url.searchParams.set("next", next);
    return NextResponse.redirect(url, { status: 303 });
  }
  const value = await mintSession(process.env.OPS_DASHBOARD_SECRET!);
  const dest = new URL(next.startsWith("/") ? next : "/", req.url);
  const res = NextResponse.redirect(dest, { status: 303 });
  res.cookies.set(COOKIE_NAME, value, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: 60 * 60 * 12, // 12h owner session
  });
  return res;
}
