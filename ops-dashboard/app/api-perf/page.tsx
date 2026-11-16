import { Shell } from "@/components/Shell";
import { DataTable, type Column } from "@/components/DataTable";
import { Panel } from "@/components/State";
import { parseScope, type SearchParams } from "@/lib/scope";
import { getApiDaily, type ApiDailyRow } from "@/lib/queries";

export const dynamic = "force-dynamic";
const pct = (v: number | null) => (v === null ? "—" : `${(v * 100).toFixed(2)}%`);
const ms = (v: number | null) => (v === null ? "—" : `${Math.round(Number(v))} ms`);

export default async function ApiPerf({ searchParams }: { searchParams: SearchParams }) {
  const scope = parseScope(searchParams);
  const daily = await getApiDaily(scope);

  const cols: Column<ApiDailyRow>[] = [
    { key: "day", label: "Day" }, { key: "env", label: "Env" },
    { key: "status_class", label: "Status", num: true, render: (r) => `${r.status_class}xx` },
    { key: "requests", label: "Requests", num: true },
    { key: "errors_4xx", label: "4xx", num: true },
    { key: "errors_5xx", label: "5xx", num: true },
    { key: "error_rate_5xx", label: "5xx rate", num: true, render: (r) => pct(r.error_rate_5xx) },
    { key: "p50_ms", label: "p50", num: true, render: (r) => ms(r.p50_ms) },
    { key: "p95_ms", label: "p95", num: true, render: (r) => ms(r.p95_ms) },
  ];

  return (
    <Shell>
      <h1>App / API performance</h1>
      <p className="sub">Scope: {scope.envs.join(" + ")} · last {scope.days} days. Per-request API metrics (DEC-098 M2).</p>
      <h2>Requests, errors & latency by day</h2>
      <p className="sub">Templated routes only — no bodies, tokens, or raw query strings are logged.</p>
      <Panel result={daily}><DataTable columns={cols} rows={daily.rows} /></Panel>
    </Shell>
  );
}
