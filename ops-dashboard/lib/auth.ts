// Owner auth gate (interim, single-owner). The session cookie holds an HMAC-SHA256 of a fixed payload
// signed with OPS_DASHBOARD_SECRET. Login compares the submitted token to OPS_DASHBOARD_TOKEN (constant
// time) and, on match, issues the cookie. The app FAILS CLOSED: if either env var is missing, login is
// refused and no data is served. This is an internal owner tool; upgrade path is Supabase-auth-as-owner
// (verify the JWT belongs to the rules_admin / owner account) — see README.
//
// Uses Web Crypto (crypto.subtle) so the identical verify runs in both the Node route handler and the
// Edge middleware.
export const COOKIE_NAME = "ops_session";
const PAYLOAD = "lanesight-ops-owner-v1";

function b64url(bytes: ArrayBuffer): string {
  const bin = String.fromCharCode(...new Uint8Array(bytes));
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function hmac(secret: string, msg: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(msg));
  return b64url(sig);
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** True only if the owner env is fully configured. When false, the app must not serve data. */
export function authConfigured(): boolean {
  return Boolean(process.env.OPS_DASHBOARD_TOKEN && process.env.OPS_DASHBOARD_SECRET);
}

/** Mint the session cookie value for a verified login. */
export async function mintSession(secret: string): Promise<string> {
  return hmac(secret, PAYLOAD);
}

/** Verify a submitted login token against OPS_DASHBOARD_TOKEN (constant time). */
export function verifyToken(submitted: string): boolean {
  const expected = process.env.OPS_DASHBOARD_TOKEN;
  if (!expected) return false;
  return constantTimeEqual(submitted, expected);
}

/** Verify a session cookie value against the expected HMAC. */
export async function verifySession(cookieValue: string | undefined): Promise<boolean> {
  const secret = process.env.OPS_DASHBOARD_SECRET;
  if (!secret || !cookieValue) return false;
  const expected = await mintSession(secret);
  return constantTimeEqual(cookieValue, expected);
}
