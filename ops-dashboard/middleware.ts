import { NextResponse, type NextRequest } from "next/server";
import { COOKIE_NAME, verifySession } from "@/lib/auth";

// Owner gate: every page/data route requires a valid session cookie. /login and the auth routes are open;
// everything else fails closed (redirect to /login) when the cookie is missing or invalid.
const OPEN_PATHS = ["/login", "/api/login", "/api/logout"];

export async function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;
  if (OPEN_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"))) {
    return NextResponse.next();
  }
  const ok = await verifySession(req.cookies.get(COOKIE_NAME)?.value);
  if (ok) return NextResponse.next();

  const url = req.nextUrl.clone();
  url.pathname = "/login";
  url.searchParams.set("next", pathname);
  return NextResponse.redirect(url);
}

export const config = {
  // Protect everything except Next internals and static assets.
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
