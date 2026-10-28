// Typed access to the canonical definitions.json (§3). Single source of truth shared with the SQL and
// the Python validator. The dashboard renders only what is declared here.
import defs from "@/definitions.json";

export type Availability = "available" | "partial" | "no_data";
export type HonestyState = "HEALTHY" | "NO_DATA" | "NO_ACCESS";

export interface MetricDef {
  id: string;
  label: string;
  view: string;
  column: string;
  unit: "count" | "ratio" | "seconds";
  domain: string;
  availability: Availability;
  formula: string;
  denominator: string | null;
  honesty: string;
}

export interface DomainDef {
  domain: string;
  availability: Availability;
}

export const DEFS = defs as unknown as {
  version: string;
  title: string;
  honesty_states: Record<HonestyState, string>;
  rules: string[];
  views: Record<string, { owner_only: boolean; real_only: boolean; grain: string; columns: string[] }>;
  domains: DomainDef[];
  metrics: MetricDef[];
  panels: { id: string; title: string; views: string[] }[];
};

export function metric(id: string): MetricDef {
  const m = DEFS.metrics.find((x) => x.id === id);
  if (!m) throw new Error(`unknown metric id: ${id}`);
  return m;
}

// Formatting that NEVER invents a value: null/undefined -> the NO DATA dash.
export function formatValue(value: number | null | undefined, unit: MetricDef["unit"]): string {
  if (value === null || value === undefined || Number.isNaN(value)) return "—";
  if (unit === "ratio") return `${(value * 100).toFixed(1)}%`;
  if (unit === "seconds") return `${value}s`;
  return value.toLocaleString();
}
