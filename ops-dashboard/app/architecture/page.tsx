import { Shell } from "@/components/Shell";
import { DataTable, type Column } from "@/components/DataTable";
import { Panel } from "@/components/State";
import { parseScope, type SearchParams } from "@/lib/scope";
import { getPlatformDaily, type PlatformDailyRow } from "@/lib/queries";

export const dynamic = "force-dynamic";
const pct = (v: number | null) => (v === null ? "—" : `${(v * 100).toFixed(1)}%`);
const s = (v: number | null) => (v === null ? "—" : `${v}s`);

export default async function Architecture({ searchParams }: { searchParams: SearchParams }) {
  const scope = parseScope(searchParams);
  const daily = await getPlatformDaily(scope);

  // Roll up to one row per platform across the window (the headline compare).
  const byPlatform = new Map<string, { attempts: number; failures: number; p50s: number[]; p90s: number[] }>();
  for (const r of daily.rows) {
    const k = r.platform || "server";
    const g = byPlatform.get(k) ?? { attempts: 0, failures: 0, p50s: [], p90s: [] };
    g.attempts += r.attempts; g.failures += r.failures;
    if (r.p50_attempt_seconds !== null) g.p50s.push(r.p50_attempt_seconds);
    if (r.p90_attempt_seconds !== null) g.p90s.push(r.p90_attempt_seconds);
    byPlatform.set(k, g);
  }
  const med = (xs: number[]) => (xs.length ? [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)] : null);
  const summary = [...byPlatform.entries()].map(([platform, g]) => ({
    platform,
    attempts: g.attempts,
    failure_rate: g.attempts ? g.failures / g.attempts : null,
    p50_attempt_seconds: med(g.p50s),
    p90_attempt_seconds: med(g.p90s),
  }));

  type Sum = (typeof summary)[number];
  const sumCols: Column<Sum>[] = [
    { key: "platform", label: "Platform" },
    { key: "attempts", label: "Attempts", num: true },
    { key: "failure_rate", label: "Fail %", num: true, render: (r) => pct(r.failure_rate) },
    { key: "p50_attempt_seconds", label: "p50", num: true, render: (r) => s(r.p50_attempt_seconds) },
    { key: "p90_attempt_seconds", label: "p90", num: true, render: (r) => s(r.p90_attempt_seconds) },
  ];
  const dailyCols: Column<PlatformDailyRow>[] = [
    { key: "day", label: "Day" }, { key: "env", label: "Env" }, { key: "platform", label: "Platform" },
    { key: "capture_mode", label: "Mode" },
    { key: "attempts", label: "Attempts", num: true },
    { key: "failures", label: "Failures", num: true },
    { key: "failure_rate", label: "Fail %", num: true, render: (r) => pct(r.failure_rate) },
    { key: "p50_attempt_seconds", label: "p50", num: true, render: (r) => s(r.p50_attempt_seconds) },
    { key: "p90_attempt_seconds", label: "p90", num: true, render: (r) => s(r.p90_attempt_seconds) },
    { key: "avg_analyze_s", label: "avg analyze", num: true, render: (r) => s(r.avg_analyze_s) },
  ];

  return (
    <Shell>
      <h1>Architecture — server vs device</h1>
      <p className="sub">
        Scope: {scope.envs.join(" + ")} · last {scope.days} days. Compares the server-authoritative engine
        (<code>platform=server</code>) with the on-device engine (<code>platform=ios</code>, shadow until the
        DEC-103 gates pass). Device rows appear once the shadow engine runs — until then this reads server-only.
      </p>
      <h2>Headline (by platform, in window)</h2>
      <Panel result={daily}><DataTable columns={sumCols} rows={summary} /></Panel>
      <h2>By day</h2>
      <Panel result={daily}><DataTable columns={dailyCols} rows={daily.rows} /></Panel>
    </Shell>
  );
}
