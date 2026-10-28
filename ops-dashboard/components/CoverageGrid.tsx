import type { CoverageRow } from "@/lib/queries";
import type { ViewResult } from "@/lib/types";
import type { HonestyState } from "@/lib/definitions";
import { StateBadge } from "./State";

const STATE_FOR = (status: string): HonestyState =>
  status === "available" ? "HEALTHY" : status === "partial" ? "NO_DATA" : "NO_ACCESS";
const LABEL = (status: string) => (status === "available" ? "available" : status === "partial" ? "partial" : "no data (pending §2)");

/**
 * Observability coverage by domain (strategy §5). Driven by ops_coverage_status, so the honest "what we
 * can and can't report yet" is read from the DB, not hard-coded in the UI. Falls back to the static
 * definitions.json domains only to render NO ACCESS structure when the DB is unreachable.
 */
export function CoverageGrid({ result }: { result: ViewResult<CoverageRow> }) {
  if (result.state === "NO_ACCESS") {
    return (
      <div className="card"><div className="empty"><StateBadge state="NO_ACCESS" /> coverage status unavailable</div></div>
    );
  }
  const rows = [...result.rows].sort((a, b) => a.domain.localeCompare(b.domain));
  return (
    <div className="cov">
      {rows.map((r) => (
        <div className="item" key={r.domain}>
          <div style={{ display: "flex", justifyContent: "space-between", gap: 8 }}>
            <span className="d">{r.domain}</span>
            <StateBadge state={STATE_FOR(r.status)} />
          </div>
          <div className="s">{LABEL(r.status)} · {r.data_source}</div>
          {r.backing_view ? <div className="s" style={{ opacity: 0.7 }}>view: {r.backing_view}</div> : null}
        </div>
      ))}
    </div>
  );
}
