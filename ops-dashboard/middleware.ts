import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { OWNER_ID, SUPABASE_URL, SUPABASE_ANON_KEY } from "@/lib/env";

// Owner gate (DEC-098). Uses Supabase Auth: verifies the session, then checks the user is the owner.
//   - not signed in            -> redirect to /login (except /login, /api/logout)
//   - signed in, NOT the owner  -> 403 everywhere (except /api/logout, so they can sign out)
//   - signed in owner           -> allowed; /login bounces to /
// This is the server-side half; every ops RPC also re-checks ops.is_owner() in Postgres.
const OPEN = ["/login", "/api/logout"];

export async function middleware(req: NextRequest) {
  let res = NextResponse.next({ request: req });

  const supabase = createServerClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    cookies: {
      getAll: () => req.cookies.getAll(),
      setAll: (toSet) => {
        toSet.forEach(({ name, value }) => req.cookies.set(name, value));
        res = NextResponse.next({ request: req });
        toSet.forEach(({ name, value, options }) => res.cookies.set(name, value, options));
      },
    },
  });

  const { data: { user } } = await supabase.auth.getUser();
  const path = req.nextUrl.pathname;
  const open = OPEN.some((p) => path === p || path.startsWith(p + "/"));

  if (!user) {
    if (open) return res;
    const url = req.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", path);
    return NextResponse.redirect(url);
  }

  if (user.id !== OWNER_ID) {
    if (path === "/api/logout") return res;
    return new NextResponse("403 — this account is not the ops owner. Sign out and use the owner account.", {
      status: 403,
      headers: { "content-type": "text/plain" },
    });
  }

  if (path === "/login") {
    const url = req.nextUrl.clone();
    url.pathname = "/";
    url.search = "";
    return NextResponse.redirect(url);
  }
  return res;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
