import type { HonestyState } from "./definitions";

export interface ViewResult<T> {
  state: HonestyState; // HEALTHY (rows present) | NO_DATA (reachable, empty) | NO_ACCESS (error/not owner)
  rows: T[];
  error?: string;
}
export type { HonestyState };
