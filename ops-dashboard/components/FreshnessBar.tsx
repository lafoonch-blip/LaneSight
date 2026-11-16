import type { FreshnessRow } from "@/lib/queries";
import type { ViewResult } from "@/lib/types";
import { StateBadge } from "./State";

function ago(iso: string | null): string {
  if (!iso) return "never";
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return "—";
  const mins = Math.max(0, Math.round((Date.now() - then) / 60000));
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 48) return `${hrs}h ago`;
  return `${Math.round(hrs / 24)}d ago`;
}

/** Per-source last-ingested clock (ops_freshness). Honest NO DATA when a source has 0 rows. */
export function FreshnessBar({ result }: { result: ViewResult<FreshnessRow> }) {
  if (result.state === "NO_ACCESS") {
    return <div className="card"><div className="empty"><StateBadge state="NO_ACCESS" /> freshness unavailable</div></div>;
  }
  return (
    <div className="tiles">
      {result.rows.map((r) => (
        <div className="tile" key={r.source}>
          <div className="label">{r.source}</div>
          <div className="value" style={{ fontSize: 18 }}>{r.rows > 0 ? ago(r.last_ingested) : "—"}</div>
          <div className="foot">
            <StateBadge state={r.rows > 0 ? "HEALTHY" : "NO_DATA"} />
            <span style={{ marginLeft: 8 }}>{r.rows.toLocaleString()} rows</span>
          </div>
        </div>
      ))}
    </div>
  );
}
