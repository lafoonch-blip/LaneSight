import { Shell } from "@/components/Shell";
import { Panel } from "@/components/State";
import { getInsights, getInsightRuns, type InsightRow } from "@/lib/queries";
import type { SearchParams } from "@/lib/scope";
import { approveInsight, setStatus, editInsight, analyzeNow } from "./actions";

export const dynamic = "force-dynamic";

// The owner triage flow (DEC-125): proposed → approved → queued → in progress → PR open → shipped,
// plus the terminal deferred / rejected / merged. Default view is the un-acted "proposed" queue.
const STATUSES = ["proposed", "approved", "queued", "in_progress", "pr_open", "shipped", "deferred", "rejected", "merged", "all"];

function thisMonthCost(rows: { started_at: string; cost_usd: number }[]): number {
  const now = new Date();
  const ym = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
  return rows
    .filter((r) => (r.started_at ?? "").slice(0, 7) === ym)
    .reduce((acc, r) => acc + (Number(r.cost_usd) || 0), 0);
}

export default async function Insights({ searchParams }: { searchParams: SearchParams }) {
  const statusParam = typeof searchParams.status === "string" ? searchParams.status : "proposed";
  const status = STATUSES.includes(statusParam) ? statusParam : "proposed";
  const [insights, runs] = await Promise.all([
    getInsights(status === "all" ? null : status),
    getInsightRuns(1),
  ]);
  const allRuns = await getInsightRuns(200);
  const lastRun = runs.rows[0];
  const monthCost = thisMonthCost(allRuns.rows);

  return (
    <Shell>
      <h1>Feedback Insights</h1>
      <p className="sub">
        AI-consolidated proposed actions from all feedback (DEC-125). Nothing is built without your approval;
        approving an item creates a <code>lanesight-queue</code> GitHub issue for review — it never changes the
        app. De-identified before the model sees it.
      </p>

      <div className="card" style={{ display: "flex", gap: 16, alignItems: "center", flexWrap: "wrap" }}>
        <form action={analyzeNow}>
          <button className="btn" type="submit">Analyze now</button>
        </form>
        <span className="sub">
          {lastRun
            ? `Last run ${new Date(lastRun.started_at).toLocaleString()} · ${lastRun.status} · ${lastRun.rows_considered} considered, ${lastRun.insights_created} new`
            : "No analyst runs yet"}
        </span>
        <span className="spacer" style={{ flex: 1 }} />
        <span className="sub">This month: ${monthCost.toFixed(2)} / $10.00 cap</span>
      </div>

      <form method="get" action="/insights" className="scope" style={{ margin: "12px 0" }}>
        <label>
          status{" "}
          <select name="status" defaultValue={status}>
            {STATUSES.map((s) => (
              <option key={s} value={s}>{s}</option>
            ))}
          </select>
        </label>
        <button className="btn" type="submit">filter</button>
      </form>

      <Panel result={insights}>
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          {insights.rows.map((ins) => (
            <InsightCard key={ins.id} ins={ins} />
          ))}
        </div>
      </Panel>
    </Shell>
  );
}

function InsightCard({ ins }: { ins: InsightRow }) {
  return (
    <div className="card">
      <div style={{ display: "flex", gap: 10, alignItems: "baseline", flexWrap: "wrap" }}>
        <strong style={{ fontSize: 16 }}>{ins.title}</strong>
        <span className="sub">{ins.type}</span>
        {ins.priority && <span className="sub">· {ins.priority}</span>}
        <span className="spacer" style={{ flex: 1 }} />
        <span className="sub">status: {ins.status}</span>
      </div>
      <div className="sub" style={{ marginTop: 4 }}>
        {ins.feedback_count} feedback · {ins.bowler_count} bowler(s)
        {ins.phases?.length ? ` · phases: ${ins.phases.join(", ")}` : ""}
        {ins.related_decs?.length ? ` · ${ins.related_decs.join(", ")}` : ""}
      </div>
      <p style={{ margin: "8px 0" }}>{ins.summary}</p>
      {ins.proposed_change && (
        <p className="sub"><strong>Proposed change:</strong> {ins.proposed_change}</p>
      )}
      {ins.github_issue_number && (
        <p className="sub">
          Queue issue{" "}
          <a href={`https://github.com/${process.env.LANESIGHT_QUEUE_REPO ?? "lafoonch-blip/LaneSight"}/issues/${ins.github_issue_number}`} target="_blank" rel="noreferrer">
            #{ins.github_issue_number}
          </a>
          {ins.pr_url && <> · <a href={ins.pr_url} target="_blank" rel="noreferrer">PR</a></>}
        </p>
      )}
      {ins.founder_notes && <p className="sub"><em>{ins.founder_notes}</em></p>}

      {/* Actions. Deferred / rejected / merged are terminal; show actions only while still open. */}
      {["proposed", "approved", "deferred"].includes(ins.status) && (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 8 }}>
          <form action={approveInsight}>
            <input type="hidden" name="id" value={ins.id} />
            <button className="btn" type="submit">Approve → queue</button>
          </form>
          <form action={setStatus}>
            <input type="hidden" name="id" value={ins.id} />
            <input type="hidden" name="status" value="deferred" />
            <button className="btn" type="submit">Defer</button>
          </form>
          <form action={setStatus} style={{ display: "flex", gap: 4 }}>
            <input type="hidden" name="id" value={ins.id} />
            <input type="hidden" name="status" value="rejected" />
            <input name="reject_reason" placeholder="reason" required />
            <button className="btn" type="submit">Reject</button>
          </form>
          <form action={setStatus} style={{ display: "flex", gap: 4 }}>
            <input type="hidden" name="id" value={ins.id} />
            <input type="hidden" name="status" value="merged" />
            <input name="merged_into" placeholder="merge into insight id" required />
            <button className="btn" type="submit">Merge</button>
          </form>
        </div>
      )}

      {/* Edit then approve — a disclosure so the card stays compact. */}
      <details style={{ marginTop: 8 }}>
        <summary className="sub">Edit</summary>
        <form action={editInsight} style={{ display: "flex", flexDirection: "column", gap: 6, marginTop: 6 }}>
          <input type="hidden" name="id" value={ins.id} />
          <input name="title" defaultValue={ins.title} placeholder="title" />
          <textarea name="summary" defaultValue={ins.summary} placeholder="summary" rows={2} />
          <textarea name="proposed_change" defaultValue={ins.proposed_change ?? ""} placeholder="proposed change" rows={2} />
          <input name="priority" defaultValue={ins.priority ?? ""} placeholder="P0-P3" />
          <button className="btn" type="submit" style={{ alignSelf: "flex-start" }}>Save edits</button>
        </form>
      </details>
    </div>
  );
}
