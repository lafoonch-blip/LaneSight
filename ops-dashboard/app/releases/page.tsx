import { Shell } from "@/components/Shell";
import { DataTable, type Column } from "@/components/DataTable";
import { Panel } from "@/components/State";
import { parseScope, type SearchParams } from "@/lib/scope";
import { getReleases, type ReleaseRow } from "@/lib/queries";

export const dynamic = "force-dynamic";
const pct = (v: number | null) => (v === null ? "—" : `${(v * 100).toFixed(1)}%`);
const date = (v: string | null) => (v ? new Date(v).toISOString().slice(0, 10) : "—");

export default async function Releases({ searchParams }: { searchParams: SearchParams }) {
  const scope = parseScope(searchParams);
  const rel = await getReleases(scope);

  const cols: Column<ReleaseRow>[] = [
    { key: "algorithm_version", label: "Engine" }, { key: "api_revision", label: "API rev" },
    { key: "env", label: "Env" }, { key: "attempts", label: "Attempts", num: true },
    { key: "failures", label: "Failures", num: true },
    { key: "failure_rate", label: "Fail %", num: true, render: (r) => pct(r.failure_rate) },
    { key: "p50_attempt_seconds", label: "p50 s", num: true },
    { key: "avg_metrics_measured", label: "Avg metrics", num: true },
    { key: "distinct_users", label: "Bowlers", num: true },
    { key: "first_seen", label: "First", render: (r) => date(r.first_seen) },
    { key: "last_seen", label: "Last", render: (r) => date(r.last_seen) },
  ];

  return (
    <Shell>
      <h1>Release & regression</h1>
      <p className="sub">
        Scope: {scope.envs.join(" + ")} · active in the last {scope.days} days · real accounts only.
        Compare failure rate / analyze time / metric coverage across engine versions (DEC-092).
      </p>
      <Panel result={rel}><DataTable columns={cols} rows={rel.rows} /></Panel>
    </Shell>
  );
}
