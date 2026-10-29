import { Shell } from "@/components/Shell";
import { DataTable, type Column } from "@/components/DataTable";
import { Panel } from "@/components/State";
import { parseScope, type SearchParams } from "@/lib/scope";
import { getPlatformDaily, type PlatformRow } from "@/lib/queries";

export const dynamic = "force-dynamic";
const pct = (v: number | null) => (v === null ? "—" : `${(v * 100).toFixed(1)}%`);

export default async function EngineCompare({ searchParams }: { searchParams: SearchParams }) {
  const scope = parseScope(searchParams);
  const plat = await getPlatformDaily(scope);

  const cols: Column<PlatformRow>[] = [
    { key: "day", label: "Day" }, { key: "env", label: "Env" },
    { key: "platform", label: "Engine" }, { key: "capture_mode", label: "Mode" },
    { key: "attempts", label: "Attempts", num: true }, { key: "analyzed", label: "Analyzed", num: true },
    { key: "failure_rate", label: "Failure", num: true, render: (r) => pct(r.failure_rate) },
    { key: "distinct_users", label: "Users", num: true },
    { key: "p50_attempt_seconds", label: "p50 s", num: true },
    { key: "p90_attempt_seconds", label: "p90 s", num: true },
    { key: "avg_analyze_s", label: "Avg analyze s", num: true },
  ];

  return (
    <Shell>
      <h1>Engine comparison — server vs on-device</h1>
      <p className="sub">
        Scope: {scope.envs.join(" + ")} · last {scope.days} days · real accounts only. Rows split by
        <b> engine</b> (<code>server</code> = authoritative Python/Cloud Run; <code>ios</code> = native on-device
        <b> shadow</b>, DEC-103/106). The on-device engine runs in the background on every shot and records here;
        it is <b>never shown to the user and never feeds Score/coaching</b>. This panel is latency/volume/failure
        only. <b>Accuracy is NOT judged server-vs-ios</b> — DEC-106 Gate A is vs <b>ground truth</b> (the DEC-094
        eval set), not vs the server; per-metric accuracy/bias/plausible-but-wrong + the flip decision live with
        the DEC-094 harness (<code>ops/cv_eval.py</code>), not here. No metric is flipped to on-device until it
        passes Gates A/B/C against ground truth.
      </p>
      <Panel result={plat}><DataTable columns={cols} rows={plat.rows} /></Panel>
    </Shell>
  );
}
