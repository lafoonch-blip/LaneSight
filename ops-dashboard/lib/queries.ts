// Typed fetchers, one per ops view, read via owner-checked RPCs (public.ops_rpc_*). Row shapes mirror the
// ops.* views in migration 025. Staged exclusion + nullif honesty live in the views; owner enforcement is
// in the RPC (and the server gate). Never throws: an RPC error -> NO_ACCESS (e.g. not signed in as owner).
import { createClient } from "./supabaseServer";
import type { ViewResult } from "./types";

export interface Scope {
  envs: string[];
  days: number;
}
export const DEFAULT_SCOPE: Scope = { envs: ["live", "beta"], days: 14 };

export interface AnalysisDailyRow {
  day: string; env: string; capture_mode: string;
  attempts: number; analyzed: number; failures: number; failure_rate: number | null;
  distinct_users: number;
  p50_attempt_seconds: number | null; p90_attempt_seconds: number | null; p95_attempt_seconds: number | null;
}
export interface FailureRow {
  day: string; env: string; capture_mode: string; failure_stage: string | null;
  failure_code: string | null; algorithm_version: string | null; failures: number;
}
export interface CvCoverageRow {
  day: string; env: string; attempts: number; far_lane_read: number; far_lane_read_rate: number | null;
  avg_metrics_measured: number | null; hdr_clips: number; vfr_clips: number; cold_start_attempts: number;
  precheck_rejects: number; precheck_evaluated: number; probe_errors: number;
}
export interface LatencyRow {
  day: string; env: string; analyzed: number;
  p50_total_s: number | null; p90_total_s: number | null; p50_server_analyze_s: number | null;
  p50_decode_s: number | null; p50_hdr_convert_s: number | null; p50_phone_trim_s: number | null;
  p50_phone_upload_s: number | null; p50_phone_pre_analyze_s: number | null; cold_start_rate: number | null;
  decode_cache_engaged_rate: number | null;
}
export interface ReleaseRow {
  algorithm_version: string | null; api_revision: string | null; env: string;
  attempts: number; failures: number; failure_rate: number | null; p50_attempt_seconds: number | null;
  avg_metrics_measured: number | null; distinct_users: number; first_seen: string; last_seen: string;
}
export interface FeedbackRow {
  day: string; app_phase: string; source: string; total: number;
  thumbs_up: number; thumbs_down: number; untriaged: number; avg_rating: number | null;
}
export interface UsageRow { day: string; shots: number; active_users_shots: number; sessions_started: number; }
export interface FreshnessRow { source: string; last_ingested: string | null; rows: number; }
export interface CoverageRow { domain: string; status: string; data_source: string; backing_view: string | null; }
// §2 instrumentation views (DEC-098, migration 027). USD/rate columns are NULL until rates/data exist — the
// table renders those as the NO DATA dash, never a fabricated number.
export interface CostDailyRow {
  day: string; env: string; attempts: number;
  vcpu_s: number | null; gib_s: number | null; egress_mb: number | null;
  est_usd: number | null; est_usd_per_success: number | null;
}
export interface ApiDailyRow {
  day: string; env: string; status_class: number; requests: number;
  errors_5xx: number; errors_4xx: number; error_rate_5xx: number | null;
  p50_ms: number | null; p95_ms: number | null;
}
export interface EventDailyRow { day: string; env: string; event_name: string; events: number; users: number; }
export interface FunnelRow { env: string; opened: number; started_session: number; first_shot: number; }
export interface StorageLatestRow {
  bucket: string; bytes: number | null; objects: number | null; aged_objects: number | null;
  db_bytes: number | null; captured_at: string | null;
}

function sinceDate(days: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
}

async function callRpc<T>(fn: string, args: Record<string, unknown>, sortBy?: keyof T): Promise<ViewResult<T>> {
  try {
    const supabase = createClient();
    const { data, error } = await supabase.rpc(fn, args);
    if (error) return { state: "NO_ACCESS", rows: [], error: `${fn}: ${error.message}` };
    let rows = (data ?? []) as T[];
    if (sortBy) {
      rows = [...rows].sort((a, b) => {
        const av = a[sortBy] as unknown, bv = b[sortBy] as unknown;
        if (typeof av === "number" && typeof bv === "number") return bv - av; // desc
        return String(bv ?? "").localeCompare(String(av ?? "")); // desc
      });
    }
    return { state: rows.length ? "HEALTHY" : "NO_DATA", rows };
  } catch (e) {
    return { state: "NO_ACCESS", rows: [], error: `${fn} failed: ${(e as Error).message}` };
  }
}

export const getAnalysisDaily = (s: Scope) =>
  callRpc<AnalysisDailyRow>("ops_rpc_analysis_daily", { p_envs: s.envs, p_since: sinceDate(s.days) }, "day");
export const getFailures = (s: Scope) =>
  callRpc<FailureRow>("ops_rpc_failure_breakdown", { p_envs: s.envs, p_since: sinceDate(s.days) }, "failures");
export const getCvCoverage = (s: Scope) =>
  callRpc<CvCoverageRow>("ops_rpc_cv_coverage", { p_envs: s.envs, p_since: sinceDate(s.days) }, "day");
export const getLatency = (s: Scope) =>
  callRpc<LatencyRow>("ops_rpc_latency_stages", { p_envs: s.envs, p_since: sinceDate(s.days) }, "day");
export const getReleases = (s: Scope) =>
  callRpc<ReleaseRow>("ops_rpc_release_health", { p_envs: s.envs, p_since: sinceDate(s.days) }, "last_seen");
export const getFeedback = (s: Scope) =>
  callRpc<FeedbackRow>("ops_rpc_feedback_summary", { p_since: sinceDate(s.days) }, "day");
export const getUsage = (s: Scope) =>
  callRpc<UsageRow>("ops_rpc_usage_daily", { p_since: sinceDate(s.days) }, "day");
export const getFreshness = () => callRpc<FreshnessRow>("ops_rpc_freshness", {}, "source");
export const getCoverage = () => callRpc<CoverageRow>("ops_rpc_coverage_status", {}, "domain");
// §2 (DEC-098) — same owner-checked RPC path. funnel takes envs only; storage takes no args.
export const getCostDaily = (s: Scope) =>
  callRpc<CostDailyRow>("ops_rpc_cost_daily", { p_envs: s.envs, p_since: sinceDate(s.days) }, "day");
export const getApiDaily = (s: Scope) =>
  callRpc<ApiDailyRow>("ops_rpc_api_daily", { p_envs: s.envs, p_since: sinceDate(s.days) }, "day");
export const getEventDaily = (s: Scope) =>
  callRpc<EventDailyRow>("ops_rpc_event_daily", { p_envs: s.envs, p_since: sinceDate(s.days) }, "day");
export const getFunnel = (s: Scope) =>
  callRpc<FunnelRow>("ops_rpc_funnel", { p_envs: s.envs }, "env");
export const getStorageLatest = () =>
  callRpc<StorageLatestRow>("ops_rpc_storage_latest", {}, "bucket");

// Sum a numeric column across rows; null (NO DATA) when there are no rows, never 0-as-fake.
export function sumCol<T>(rows: T[], col: keyof T): number | null {
  if (!rows.length) return null;
  return rows.reduce((acc, r) => acc + (Number(r[col]) || 0), 0);
}

// Weighted rate: numerator / denominator across rows; null when denominator is 0 (NO DATA).
export function weightedRate<T>(rows: T[], numeratorCol: keyof T, denomCol: keyof T): number | null {
  const denom = rows.reduce((a, r) => a + (Number(r[denomCol]) || 0), 0);
  if (denom === 0) return null;
  const num = rows.reduce((a, r) => a + (Number(r[numeratorCol]) || 0), 0);
  return num / denom;
}
