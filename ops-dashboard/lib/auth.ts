import type { SupabaseClient, User } from "@supabase/supabase-js";
import { OWNER_ID } from "./env";

// The owner check (DEC-098). Mirrors ops.is_owner() in the DB — defense in depth: the server gates here,
// and every RPC re-checks in Postgres. Owner id comes from OPS_OWNER_ID (== owner.py OWNER_USER_ID).
export function isOwner(user: User | null | undefined): boolean {
  return Boolean(user && OWNER_ID && user.id === OWNER_ID);
}

/** Return the signed-in user iff they are the owner; otherwise null. */
export async function getOwnerUser(supabase: SupabaseClient): Promise<User | null> {
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return null;
  return isOwner(data.user) ? data.user : null;
}
