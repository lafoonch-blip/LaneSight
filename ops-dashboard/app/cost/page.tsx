import { Shell } from "@/components/Shell";
import { DataTable, type Column } from "@/components/DataTable";
import { Panel } from "@/components/State";
import { parseScope, type SearchParams } from "@/lib/scope";
import { getCostDaily, type CostDailyRow } from "@/lib/queries";

export const dynamic = "force-dynamic";
const usd = (v: number | null) => (v === null ? "—" : `$${Number(v).toFixed(2)}`);
const usd4 = (v: number | null) => (v === null ? "—" : `$${Number(v).toFixed(4)}`);
const num1 = (v: number | null) => (v === null ? "—" : Number(v).toLocaleString(undefined, { maximumFractionDigits: 1 }));

export default async function Cost({ searchParams }: { searchParams: SearchParams }) {
  const scope = parseScope(searchParams);
  const daily = await getCostDaily(scope);

  const cols: Column<CostDailyRow>[] = [
    { key: "day", label: "Day" }, { key: "env", label: "Env" },
    { key: "attempts", label: "Attempts", num: true },
    { key: "vcpu_s", label: "vCPU-s", num: true, render: (r) => num1(r.vcpu_s) },
    { key: "gib_s", label: "GiB-s", num: true, render: (r) => num1(r.gib_s) },
    { key: "egress_mb", label: "Egress MB", num: true, render: (r) => num1(r.egress_mb) },
    { key: "est_usd", label: "Est. USD", num: true, render: (r) => usd(r.est_usd) },
    { key: "est_usd_per_success", label: "USD / success", num: true, render: (r) => usd4(r.est_usd_per_success) },
  ];

  return (
    <Shell>
      <h1>Financial operations</h1>
      <p className="sub">Scope: {scope.envs.join(" + ")} · last {scope.days} days · real accounts only.</p>
      <h2>Compute cost by day</h2>
      <p className="sub">
        Resource-seconds are measured per analysis. USD is computed from <code>ops.cost_rates</code> and shows
        NO DATA until sourced Cloud Run rates are entered — a dollar value is never invented.
      </p>
      <Panel result={daily}><DataTable columns={cols} rows={daily.rows} /></Panel>
    </Shell>
  );
}
