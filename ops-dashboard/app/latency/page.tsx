import { Shell } from "@/components/Shell";
import { DataTable, type Column } from "@/components/DataTable";
import { Panel } from "@/components/State";
import { parseScope, type SearchParams } from "@/lib/scope";
import { getLatency, type LatencyRow } from "@/lib/queries";

export const dynamic = "force-dynamic";
const pct = (v: number | null) => (v === null ? "—" : `${(v * 100).toFixed(1)}%`);

export default async function Latency({ searchParams }: { searchParams: SearchParams }) {
  const scope = parseScope(searchParams);
  const lat = await getLatency(scope);

  const cols: Column<LatencyRow>[] = [
    { key: "day", label: "Day" }, { key: "env", label: "Env" }, { key: "analyzed", label: "Analyzed", num: true },
    { key: "p50_total_s", label: "Total p50", num: true }, { key: "p90_total_s", label: "Total p90", num: true },
    { key: "p50_server_analyze_s", label: "Server p50", num: true },
    { key: "p50_decode_s", label: "Decode p50", num: true },
    { key: "p50_hdr_convert_s", label: "HDR cvt p50", num: true },
    { key: "p50_phone_trim_s", label: "Trim p50", num: true },
    { key: "p50_phone_upload_s", label: "Upload p50", num: true },
    { key: "p50_phone_pre_analyze_s", label: "Phone pre p50", num: true },
    { key: "cold_start_rate", label: "Cold start", num: true, render: (r) => pct(r.cold_start_rate) },
  ];

  return (
    <Shell>
      <h1>Latency by stage</h1>
      <p className="sub">
        Scope: {scope.envs.join(" + ")} · last {scope.days} days · analyzed attempts, real accounts only.
        A blank stage means it was never timed in the window (NO DATA) — e.g. HDR convert on an all-SDR day.
      </p>
      <Panel result={lat}><DataTable columns={cols} rows={lat.rows} /></Panel>
    </Shell>
  );
}
