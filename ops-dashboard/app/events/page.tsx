import { Shell } from "@/components/Shell";
import { DataTable, type Column } from "@/components/DataTable";
import { Panel } from "@/components/State";
import { parseScope, type SearchParams } from "@/lib/scope";
import { getFunnel, getEventDaily, type FunnelRow, type EventDailyRow } from "@/lib/queries";

export const dynamic = "force-dynamic";
const rate = (num: number, denom: number) => (denom ? `${((num / denom) * 100).toFixed(1)}%` : "—");

export default async function Events({ searchParams }: { searchParams: SearchParams }) {
  const scope = parseScope(searchParams);
  const [funnel, events] = await Promise.all([getFunnel(scope), getEventDaily(scope)]);

  const funnelCols: Column<FunnelRow>[] = [
    { key: "env", label: "Env" },
    { key: "opened", label: "Opened", num: true },
    { key: "started_session", label: "Started session", num: true },
    { key: "first_shot", label: "First shot", num: true },
    { key: "r_open_session", label: "Open → session", num: true, render: (r) => rate(r.started_session, r.opened) },
    { key: "r_session_shot", label: "Session → shot", num: true, render: (r) => rate(r.first_shot, r.started_session) },
  ];
  const eventCols: Column<EventDailyRow>[] = [
    { key: "day", label: "Day" }, { key: "env", label: "Env" },
    { key: "event_name", label: "Event" },
    { key: "events", label: "Events", num: true },
    { key: "users", label: "Users", num: true },
  ];

  return (
    <Shell>
      <h1>Customer journey</h1>
      <p className="sub">Scope: {scope.envs.join(" + ")} · last {scope.days} days. Consent-aware product events (DEC-098 M3).</p>
      <h2>Activation funnel</h2>
      <p className="sub">app_opened → session_started → first_shot_analyzed, by env. Pseudonymous users, real accounts only.</p>
      <Panel result={funnel}><DataTable columns={funnelCols} rows={funnel.rows} /></Panel>
      <h2>Events by day</h2>
      <Panel result={events}><DataTable columns={eventCols} rows={events.rows} /></Panel>
    </Shell>
  );
}
