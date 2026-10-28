import { DEFAULT_SCOPE, type Scope } from "./queries";

export type SearchParams = { [key: string]: string | string[] | undefined };

const VALID_ENVS = ["live", "beta", "dev"];
const VALID_DAYS = [7, 14, 30, 90];

/** Parse ?env=live,beta&days=14 into a Scope, clamping to known-safe values. Defaults to live+beta / 14d. */
export function parseScope(sp: SearchParams): Scope {
  const envRaw = typeof sp.env === "string" ? sp.env : DEFAULT_SCOPE.envs.join(",");
  const envs = envRaw.split(",").map((e) => e.trim()).filter((e) => VALID_ENVS.includes(e));
  const daysRaw = Number(typeof sp.days === "string" ? sp.days : DEFAULT_SCOPE.days);
  const days = VALID_DAYS.includes(daysRaw) ? daysRaw : DEFAULT_SCOPE.days;
  return { envs: envs.length ? envs : DEFAULT_SCOPE.envs, days };
}

/** Serialize a scope back to a query string for links. */
export function scopeQuery(s: Scope): string {
  return `env=${s.envs.join(",")}&days=${s.days}`;
}
