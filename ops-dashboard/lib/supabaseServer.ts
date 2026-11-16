import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./env";

// Supabase client for Server Components / route handlers. Reads the owner's session from cookies and
// attaches their JWT to PostgREST calls, so RPCs run with auth.uid() = the signed-in user. In an RSC the
// cookie store is read-only; setAll is wrapped in try/catch (token refresh is handled in middleware).
export function createClient() {
  const store = cookies();
  return createServerClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (toSet) => {
        try {
          toSet.forEach(({ name, value, options }) => store.set(name, value, options));
        } catch {
          /* called from an RSC — ignore; middleware refreshes cookies */
        }
      },
    },
  });
}
