import { Shell } from "@/components/Shell";
import { StatTile } from "@/components/StatTile";
import { DataTable, type Column } from "@/components/DataTable";
import { FreshnessBar } from "@/components/FreshnessBar";
import { CoverageGrid } from "@/components/CoverageGrid";
import { Panel } from "@/components/State";
import { metric } from "@/lib/definitions";
import { parseScope, type SearchParams } from "@/lib/scope";
import {
  getAnalysisDaily, getUsage, getFreshness, getCoverage, sumCol, weightedRate,
  type AnalysisDailyRow,
} from "@/lib/queries";

export const dynamic = "force-dynamic";

function pct(v: number | null | undefined): string {
  return v === null || v === undefined ? "—" : `${(v * 100).toFixed(1)}%`;
}

export default async function Overview({ searchParams }: { searchParams: SearchParams }) {
  const scope = parseScope(searchParams);
  const [daily, usage, fresh, cov] = await Promise.all([
    getAnalysisDaily(scope), getUsage(scope), getFreshness(), getCoverage(),
  ]);

  const attempts = sumCol(daily.rows, "attempts");
  const failRate = weightedRate(daily.rows, "failures", "attempts");
  const shots = sumCol(usage.rows, "shots");
  const sessions = sumCol(usage.rows, "sessions_started");

  const cols: Column<AnalysisDailyRow>[] = [
    { key: "day", label: "Day" },
    { key: "env", label: "Env" },
    { key: "capture_mode", label: "Mode" },
    { key: "attempts", label: "Attempts", num: true },
    { key: "analyzed", label: "Analyzed", num: true },
    { key: "failures", label: "Failures", num: true },
    { key: "failure_rate", label: "Fail %", num: true, render: (r) => pct(r.failure_rate) },
    { key: "p90_attempt_seconds", label: "p90 s", num: true },
    { key: "distinct_users", label: "Bowlers", num: true },
  ];

  return (
    <Shell>
      <h1>Overview</h1>
      <p className="sub">
        Scope: {scope.envs.join(" + ")} · last {scope.days} days. Real accounts only (staged excluded).
      </p>

      <div className="tiles">
        <StatTile def={metric("attempts")} value={attempts} state={daily.state} foot="in window" />
        <StatTile def={metric("failure_rate")} value={failRate} state={daily.state} foot="attempt-weighted" />
        <StatTile def={metric("shots")} value={shots} state={usage.state} foot="in window" />
        <StatTile def={metric("sessions_started")} value={sessions} state={usage.state} foot="in window" />
      </div>

      <h2>Freshness</h2>
      <FreshnessBar result={fresh} />

      <h2>Analysis by day</h2>
      <Panel result={daily}><DataTable columns={cols} rows={daily.rows} /></Panel>

      <h2>Observability coverage</h2>
      <p className="sub">Which of the 8 strategy domains have real instrumentation today. NO DATA domains await §2.</p>
      <CoverageGrid result={cov} />
    </Shell>
  );
}
