import type { ReactNode } from "react";
import type { HonestyState } from "@/lib/definitions";
import type { ViewResult } from "@/lib/types";

export function StateBadge({ state }: { state: HonestyState }) {
  const label = state === "HEALTHY" ? "LIVE" : state === "NO_DATA" ? "NO DATA" : "NO ACCESS";
  return (
    <span className={`state ${state}`}>
      <span className="dot" /> {label}
    </span>
  );
}

/**
 * Renders children only when the result is HEALTHY. For NO_DATA / NO_ACCESS it renders the honest empty
 * state — never a fabricated value. `error` is shown for NO_ACCESS so the owner can fix the connection.
 */
export function Panel<T>({ result, children }: { result: ViewResult<T>; children: ReactNode }) {
  if (result.state === "HEALTHY") return <>{children}</>;
  if (result.state === "NO_DATA") {
    return <div className="card"><div className="empty">No data in the selected window.</div></div>;
  }
  return (
    <div className="card">
      <div className="empty">
        <StateBadge state="NO_ACCESS" />
        <div style={{ marginTop: 8 }}>Could not reach the database.</div>
        {result.error ? <div style={{ fontSize: 12, marginTop: 6, opacity: 0.8 }}>{result.error}</div> : null}
      </div>
    </div>
  );
}
