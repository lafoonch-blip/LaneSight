"use client";
import { createBrowserClient } from "@supabase/ssr";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./env";

// Browser client — used only on the login page for signInWithPassword. Session is persisted to cookies
// (shared with the server client) by @supabase/ssr.
export function createClient() {
  return createBrowserClient(SUPABASE_URL, SUPABASE_ANON_KEY);
}
