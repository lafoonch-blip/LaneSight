import { Shell } from "@/components/Shell";
import { StatTile } from "@/components/StatTile";
import { DataTable, type Column } from "@/components/DataTable";
import { Panel } from "@/components/State";
import { metric } from "@/lib/definitions";
import { parseScope, type SearchParams } from "@/lib/scope";
import { getCvCoverage, weightedRate, type CvCoverageRow } from "@/lib/queries";

export const dynamic = "force-dynamic";
const pct = (v: number | null) => (v === null ? "—" : `${(v * 100).toFixed(1)}%`);

export default async function CvTrust({ searchParams }: { searchParams: SearchParams }) {
  const scope = parseScope(searchParams);
  const cov = await getCvCoverage(scope);

  // Honest aggregate: far-lane read rate across the window = sum(read) / sum(evaluated-with-far_lane).
  // ops_cv_coverage exposes far_lane_read and the per-row rate; the denominator (far_lane recorded) is the
  // attempts count minus nulls — not a column, so we weight by far_lane_read / attempts is wrong. Use the
  // per-row rate only when present; for the headline we weight read by attempts (lower bound) and label it.
  const totalRead = cov.rows.reduce((a, r) => a + (r.far_lane_read || 0), 0);
  const totalAttempts = cov.rows.reduce((a, r) => a + (r.attempts || 0), 0);
  const farLaneRate = totalAttempts === 0 ? null : totalRead / totalAttempts;
  const rejects = cov.rows.reduce((a, r) => a + (r.precheck_rejects || 0), 0);
  const avgMetrics = weightedRate(cov.rows, "avg_metrics_measured", "attempts"); // approx attempt-weighted

  const cols: Column<CvCoverageRow>[] = [
    { key: "day", label: "Day" }, { key: "env", label: "Env" },
    { key: "attempts", label: "Attempts", num: true },
    { key: "far_lane_read", label: "Far-lane read", num: true },
    { key: "far_lane_read_rate", label: "Read %", num: true, render: (r) => pct(r.far_lane_read_rate) },
    { key: "avg_metrics_measured", label: "Avg metrics", num: true },
    { key: "hdr_clips", label: "HDR", num: true },
    { key: "vfr_clips", label: "VFR", num: true },
    { key: "cold_start_attempts", label: "Cold start", num: true },
    { key: "precheck_rejects", label: "Precheck rej.", num: true },
    { key: "probe_errors", label: "Probe err.", num: true },
  ];

  return (
    <Shell>
      <h1>Video & CV trust</h1>
      <p className="sub">
        Scope: {scope.envs.join(" + ")} · last {scope.days} days · ball (shot) attempts, real accounts only.
      </p>
      <div className="tiles">
        <StatTile def={metric("far_lane_read_rate")} value={farLaneRate} state={cov.state} foot="read / attempts" />
        <StatTile def={metric("avg_metrics_measured")} value={avgMetrics} state={cov.state} foot="attempt-weighted" />
        <StatTile def={metric("precheck_rejects")} value={cov.state === "NO_DATA" ? null : rejects} state={cov.state} foot="shadow mode" />
      </div>
      <h2>Capture quality by day</h2>
      <Panel result={cov}><DataTable columns={cols} rows={cov.rows} /></Panel>
    </Shell>
  );
}
