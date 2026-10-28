import type { HonestyState, MetricDef } from "@/lib/definitions";
import { formatValue } from "@/lib/definitions";
import { StateBadge } from "./State";

/**
 * A headline number tied to a metric definition. `value === null` renders the NO DATA dash — the tile
 * never invents a number. `state` reflects reachability (NO_ACCESS when the DB is down).
 */
export function StatTile({
  def, value, state, foot,
}: {
  def: MetricDef;
  value: number | null;
  state: HonestyState;
  foot?: string;
}) {
  const shown: HonestyState = state === "NO_ACCESS" ? "NO_ACCESS" : value === null ? "NO_DATA" : "HEALTHY";
  return (
    <div className="tile" title={`${def.formula}${def.denominator ? ` · denominator: ${def.denominator}` : ""}`}>
      <div className="label">{def.label}</div>
      <div className="value">{state === "NO_ACCESS" ? "—" : formatValue(value, def.unit)}</div>
      <div className="foot">
        <StateBadge state={shown} />
        {foot ? <span style={{ marginLeft: 8 }}>{foot}</span> : null}
      </div>
    </div>
  );
}
