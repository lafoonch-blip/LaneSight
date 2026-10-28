import { authConfigured } from "@/lib/auth";
import type { SearchParams } from "@/lib/scope";

export const dynamic = "force-dynamic";

export default function LoginPage({ searchParams }: { searchParams: SearchParams }) {
  const configured = authConfigured();
  const error = searchParams.error === "1";
  const next = typeof searchParams.next === "string" ? searchParams.next : "/";
  return (
    <div className="login">
      <h1>LaneSight Ops</h1>
      <p className="sub">Owner-only. Real production signals; no mock numbers.</p>
      {!configured ? (
        <p className="cfg">
          Owner auth is not configured. Set <code>OPS_DASHBOARD_TOKEN</code> and{" "}
          <code>OPS_DASHBOARD_SECRET</code> (see <code>.env.example</code>) and restart. The dashboard
          serves no data until then.
        </p>
      ) : (
        <form method="post" action="/api/login">
          {error ? <div className="err">Incorrect token.</div> : null}
          <input type="password" name="token" placeholder="Owner token" autoFocus autoComplete="off" />
          <input type="hidden" name="next" value={next} />
          <button className="btn" type="submit" style={{ width: "100%" }}>Enter</button>
        </form>
      )}
    </div>
  );
}
