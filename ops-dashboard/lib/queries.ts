// Typed fetchers, one per ops view. Row shapes mirror the columns in definitions.json / 0XX_ops_reporting.sql.
// All filtering is pushed to PostgREST; staged exclusion + nullif honesty live in the views themselves.
import { selectView, sinceFilter, envFilter, type ViewResult } from "./supabase";

export interface Scope {
  envs: string[]; // e.g. ["live","beta"]
  days: number; // lookback window
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

const scoped = (s: Scope, dayCol = "day") => `${sinceFilter(dayCol, s.days)}&${envFilter(s.envs)}`;

export const getAnalysisDaily = (s: Scope): Promise<ViewResult<AnalysisDailyRow>> =>
  selectView<AnalysisDailyRow>("ops_analysis_daily", `${scoped(s)}&order=day.desc`);

export const getFailures = (s: Scope): Promise<ViewResult<FailureRow>> =>
  selectView<FailureRow>("ops_failure_breakdown", `${scoped(s)}&order=failures.desc`);

export const getCvCoverage = (s: Scope): Promise<ViewResult<CvCoverageRow>> =>
  selectView<CvCoverageRow>("ops_cv_coverage", `${scoped(s)}&order=day.desc`);

export const getLatency = (s: Scope): Promise<ViewResult<LatencyRow>> =>
  selectView<LatencyRow>("ops_latency_stages", `${scoped(s)}&order=day.desc`);

export const getReleases = (s: Scope): Promise<ViewResult<ReleaseRow>> =>
  // ops_release_health has no `day`; filter env + last_seen window.
  selectView<ReleaseRow>("ops_release_health", `${sinceFilter("last_seen", s.days)}&${envFilter(s.envs)}&order=last_seen.desc`);

export const getFeedback = (s: Scope): Promise<ViewResult<FeedbackRow>> =>
  // feedback is phased (app_phase), not env; filter by day only.
  selectView<FeedbackRow>("ops_feedback_summary", `${sinceFilter("day", s.days)}&order=day.desc`);

export const getUsage = (s: Scope): Promise<ViewResult<UsageRow>> =>
  selectView<UsageRow>("ops_usage_daily", `${sinceFilter("day", s.days)}&order=day.desc`);

export const getFreshness = (): Promise<ViewResult<FreshnessRow>> =>
  selectView<FreshnessRow>("ops_freshness", "order=source.asc");

export const getCoverage = (): Promise<ViewResult<CoverageRow>> =>
  selectView<CoverageRow>("ops_coverage_status", "order=domain.asc");

// Sum a numeric column across scoped daily rows (for headline tiles). Returns null when there are no rows
// (NO DATA), never 0-as-fake.
export function sumCol<T>(rows: T[], col: keyof T): number | null {
  if (!rows.length) return null;
  return rows.reduce((acc, r) => acc + (Number(r[col]) || 0), 0);
}

// Attempt-weighted mean of a rate column across daily rows (so a global failure_rate is honest, not a
// mean-of-means). Returns null when the denominator is 0 (NO DATA).
export function weightedRate<T>(
  rows: T[], numeratorCol: keyof T, denomCol: keyof T,
): number | null {
  const denom = rows.reduce((a, r) => a + (Number(r[denomCol]) || 0), 0);
  if (denom === 0) return null;
  const num = rows.reduce((a, r) => a + (Number(r[numeratorCol]) || 0), 0);
  return num / denom;
}
