// Public (client-safe) Supabase config. The anon/publishable key is designed to be shipped to the browser;
// it grants no privileged access on its own — every ops read goes through an owner-checked RPC, and the
// ops schema is unreachable by anon/authenticated. No service_role / JWT secret / DB password is ever used.
export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
export const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

// Owner id — must equal owner.py OWNER_USER_ID and ops.app_owner. Server-side gate (defense in depth; the
// DB RPC also enforces it).
export const OWNER_ID = process.env.OPS_OWNER_ID ?? "";

export function publicEnvReady(): boolean {
  return Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);
}
