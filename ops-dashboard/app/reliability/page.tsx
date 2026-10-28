import { Shell } from "@/components/Shell";
import { DataTable, type Column } from "@/components/DataTable";
import { Panel } from "@/components/State";
import { parseScope, type SearchParams } from "@/lib/scope";
import { getAnalysisDaily, getFailures, type AnalysisDailyRow, type FailureRow } from "@/lib/queries";

export const dynamic = "force-dynamic";
const pct = (v: number | null) => (v === null ? "—" : `${(v * 100).toFixed(1)}%`);

export default async function Reliability({ searchParams }: { searchParams: SearchParams }) {
  const scope = parseScope(searchParams);
  const [daily, fails] = await Promise.all([getAnalysisDaily(scope), getFailures(scope)]);

  const dailyCols: Column<AnalysisDailyRow>[] = [
    { key: "day", label: "Day" }, { key: "env", label: "Env" }, { key: "capture_mode", label: "Mode" },
    { key: "attempts", label: "Attempts", num: true }, { key: "failures", label: "Failures", num: true },
    { key: "failure_rate", label: "Fail %", num: true, render: (r) => pct(r.failure_rate) },
    { key: "p50_attempt_seconds", label: "p50 s", num: true },
    { key: "p90_attempt_seconds", label: "p90 s", num: true },
    { key: "p95_attempt_seconds", label: "p95 s", num: true },
  ];
  const failCols: Column<FailureRow>[] = [
    { key: "day", label: "Day" }, { key: "env", label: "Env" }, { key: "capture_mode", label: "Mode" },
    { key: "failure_stage", label: "Stage" }, { key: "failure_code", label: "Code" },
    { key: "algorithm_version", label: "Engine" }, { key: "failures", label: "Count", num: true },
  ];

  return (
    <Shell>
      <h1>Analysis reliability</h1>
      <p className="sub">Scope: {scope.envs.join(" + ")} · last {scope.days} days · real accounts only.</p>
      <h2>Attempts & failure rate by day</h2>
      <Panel result={daily}><DataTable columns={dailyCols} rows={daily.rows} /></Panel>
      <h2>Failure breakdown</h2>
      <p className="sub">What is failing, where, on which engine version.</p>
      <Panel result={fails}><DataTable columns={failCols} rows={fails.rows} /></Panel>
    </Shell>
  );
}
