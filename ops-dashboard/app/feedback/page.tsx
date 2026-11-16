import { Shell } from "@/components/Shell";
import { StatTile } from "@/components/StatTile";
import { DataTable, type Column } from "@/components/DataTable";
import { Panel } from "@/components/State";
import { metric } from "@/lib/definitions";
import { parseScope, type SearchParams } from "@/lib/scope";
import { getFeedback, sumCol, type FeedbackRow } from "@/lib/queries";

export const dynamic = "force-dynamic";

export default async function Feedback({ searchParams }: { searchParams: SearchParams }) {
  const scope = parseScope(searchParams);
  const fb = await getFeedback(scope);

  const untriaged = sumCol(fb.rows, "untriaged");
  const down = sumCol(fb.rows, "thumbs_down");

  const cols: Column<FeedbackRow>[] = [
    { key: "day", label: "Day" }, { key: "app_phase", label: "Phase" }, { key: "source", label: "Source" },
    { key: "total", label: "Total", num: true },
    { key: "thumbs_up", label: "👍", num: true }, { key: "thumbs_down", label: "👎", num: true },
    { key: "untriaged", label: "Untriaged", num: true },
    { key: "avg_rating", label: "Avg rating", num: true },
  ];

  return (
    <Shell>
      <h1>Feedback & support</h1>
      <p className="sub">
        Last {scope.days} days · real feedback only (staged excluded). Feedback is phased (dev/beta/live),
        not env-scoped, so the env filter does not apply here.
      </p>
      <div className="tiles">
        <StatTile def={metric("feedback_untriaged")} value={untriaged} state={fb.state} foot="triage_status = new" />
        <StatTile def={{ ...metric("feedback_untriaged"), id: "down", label: "Thumbs down" }} value={down} state={fb.state} foot="advice 👎" />
      </div>
      <h2>Feedback by day</h2>
      <Panel result={fb}><DataTable columns={cols} rows={fb.rows} /></Panel>
    </Shell>
  );
}
