"use server";
// DEC-125 §3/§4: owner-only mutations for Feedback Insights. Every write re-checks the owner server-side
// (getOwnerUser) and runs against the owner's JWT, so the feedback_insight RLS policy (ops.is_owner()) is
// the DB-level gate (defense in depth). Nothing here changes the app — approval only creates a work-queue
// issue for Shayne to review (DEC-059 "no live effect").
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabaseServer";
import { getOwnerUser } from "@/lib/auth";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createQueueIssue, githubConfigured } from "./github";

async function ownerClient(): Promise<SupabaseClient> {
  const supabase = createClient();
  const owner = await getOwnerUser(supabase);
  if (!owner) throw new Error("not authorized");
  return supabase;
}

/** Defer / Reject / Merge — a simple status change, with optional reason / merge target / notes. */
export async function setStatus(formData: FormData) {
  const id = String(formData.get("id"));
  const status = String(formData.get("status"));
  const supabase = await ownerClient();
  const patch: Record<string, unknown> = { status };
  const reason = formData.get("reject_reason");
  const mergedInto = formData.get("merged_into");
  const notes = formData.get("founder_notes");
  if (reason) patch.reject_reason = String(reason);
  if (mergedInto) patch.merged_into = String(mergedInto);
  if (notes) patch.founder_notes = String(notes);
  await supabase.from("feedback_insight").update(patch).eq("id", id);
  revalidatePath("/insights");
}

/** Edit then (optionally) keep reviewing — change the title / summary / proposed change / priority. */
export async function editInsight(formData: FormData) {
  const id = String(formData.get("id"));
  const supabase = await ownerClient();
  const patch: Record<string, unknown> = {};
  for (const k of ["title", "summary", "proposed_change", "priority"] as const) {
    const v = formData.get(k);
    if (v !== null && String(v).trim() !== "") patch[k] = String(v);
  }
  if (Object.keys(patch).length) {
    await supabase.from("feedback_insight").update(patch).eq("id", id);
  }
  revalidatePath("/insights");
}

/** Approve → create the queue issue. Without GITHUB_TOKEN the insight stays `approved` and a note records
 * that the issue couldn't be created yet (so it's retried once the token is set). */
export async function approveInsight(formData: FormData) {
  const id = String(formData.get("id"));
  const supabase = await ownerClient();
  await supabase
    .from("feedback_insight")
    .update({ status: "approved", approved_at: new Date().toISOString() })
    .eq("id", id);

  // Evidence counts come from the owner-checked RPC (same source the list uses).
  const { data: list } = await supabase.rpc("ops_rpc_feedback_insights", { p_status: null });
  const row = (list ?? []).find((r: { id: string }) => r.id === id);
  if (!row) {
    revalidatePath("/insights");
    return;
  }
  if (!githubConfigured()) {
    await supabase
      .from("feedback_insight")
      .update({ founder_notes: "Approved — GITHUB_TOKEN not set yet, queue issue pending." })
      .eq("id", id);
    revalidatePath("/insights");
    return;
  }
  try {
    const number = await createQueueIssue({
      id: row.id, title: row.title, type: row.type, summary: row.summary,
      proposed_change: row.proposed_change, affected_area: row.affected_area,
      priority: row.priority, related_decs: row.related_decs ?? [],
      feedback_count: row.feedback_count ?? 0, bowler_count: row.bowler_count ?? 0,
      phases: row.phases ?? [],
    });
    await supabase
      .from("feedback_insight")
      .update({ status: "queued", github_issue_number: number })
      .eq("id", id);
  } catch (e) {
    await supabase
      .from("feedback_insight")
      .update({ founder_notes: `Queue issue failed: ${(e as Error).message}`.slice(0, 480) })
      .eq("id", id);
  }
  revalidatePath("/insights");
}

/** "Analyze now" — trigger the Python analyst job via its owner-gated endpoint, forwarding the owner's
 * Supabase JWT (the API verifies it the same way). The $10/month cost cap is enforced inside the job. */
export async function analyzeNow() {
  const supabase = await ownerClient();
  const { data } = await supabase.auth.getSession();
  const base = process.env.LANESIGHT_API_URL ?? "https://lanesight-api-665597641318.us-east1.run.app";
  if (data.session?.access_token) {
    try {
      await fetch(`${base}/ops/insights/analyze`, {
        method: "POST",
        headers: { Authorization: `Bearer ${data.session.access_token}` },
      });
    } catch {
      /* best-effort trigger; the daily Cloud Scheduler run is the backstop */
    }
  }
  revalidatePath("/insights");
}
