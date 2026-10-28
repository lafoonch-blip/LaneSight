// SERVER-ONLY Supabase access. Reads the owner-only ops_* views over PostgREST with the service_role key
// (bypasses RLS). This module must never be imported into a Client Component — the key is read from a
// non-NEXT_PUBLIC_ env var, so Next will not bundle it for the browser, and we keep all callers in RSC /
// route handlers. No @supabase/supabase-js dependency: a plain fetch keeps the surface tiny and offline.
import type { HonestyState } from "./definitions";

export interface ViewResult<T> {
  state: HonestyState; // HEALTHY (rows present) | NO_DATA (reachable, empty) | NO_ACCESS (unreachable)
  rows: T[];
  error?: string;
}

function config(): { url: string; key: string } | null {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  return { url: url.replace(/\/$/, ""), key };
}

/** True when the dashboard is configured to reach a DB at all. */
export function dbConfigured(): boolean {
  return config() !== null;
}

/**
 * SELECT from an ops view. `query` is a raw PostgREST query string (e.g. "env=in.(live,beta)&order=day.desc").
 * Never throws: a missing key or a failed request yields NO_ACCESS so the UI can render that state honestly
 * instead of fabricating numbers.
 */
export async function selectView<T = Record<string, unknown>>(
  view: string,
  query = "",
): Promise<ViewResult<T>> {
  const cfg = config();
  if (!cfg) return { state: "NO_ACCESS", rows: [], error: "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set" };

  const sep = query ? "?" : "";
  const target = `${cfg.url}/rest/v1/${view}${sep}${query}`;
  try {
    const res = await fetch(target, {
      headers: {
        apikey: cfg.key,
        Authorization: `Bearer ${cfg.key}`,
        Accept: "application/json",
      },
      cache: "no-store",
    });
    if (!res.ok) {
      const body = (await res.text()).slice(0, 300);
      return { state: "NO_ACCESS", rows: [], error: `PostgREST ${view} -> ${res.status}: ${body}` };
    }
    const rows = (await res.json()) as T[];
    return { state: rows.length ? "HEALTHY" : "NO_DATA", rows };
  } catch (e) {
    return { state: "NO_ACCESS", rows: [], error: `fetch ${view} failed: ${(e as Error).message}` };
  }
}

/** PostgREST filter for "created_at/day within the last N days". Returns e.g. "day=gte.2026-10-14". */
export function sinceFilter(column: string, days: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - days);
  const iso = d.toISOString().slice(0, 10);
  return `${column}=gte.${iso}`;
}

/** PostgREST "in" filter for an env list, e.g. ["live","beta"] -> "env=in.(live,beta)". */
export function envFilter(envs: string[]): string {
  return `env=in.(${envs.join(",")})`;
}
