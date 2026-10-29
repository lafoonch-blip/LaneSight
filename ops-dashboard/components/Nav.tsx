"use client";
import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";

const LINKS = [
  { href: "/", label: "Overview" },
  { href: "/reliability", label: "Reliability" },
  { href: "/cv-trust", label: "CV Trust" },
  { href: "/latency", label: "Latency" },
  { href: "/api-perf", label: "API" },
  { href: "/cost", label: "Cost" },
  { href: "/events", label: "Journey" },
  { href: "/storage", label: "Storage" },
  { href: "/architecture", label: "Architecture" },
  { href: "/releases", label: "Releases" },
  { href: "/feedback", label: "Feedback" },
];

export function Nav() {
  const pathname = usePathname();
  const sp = useSearchParams();
  const qs = sp.toString();
  const withScope = (href: string) => (qs ? `${href}?${qs}` : href);

  const env = sp.get("env") ?? "live,beta";
  const days = sp.get("days") ?? "14";

  return (
    <nav className="nav">
      <div className="nav-inner">
        <span className="brand">LaneSight Ops <small>owner-only · real signals</small></span>
        <div className="links">
          {LINKS.map((l) => (
            <Link key={l.href} href={withScope(l.href)} className={pathname === l.href ? "active" : ""}>
              {l.label}
            </Link>
          ))}
        </div>
        <span className="spacer" />
        {/* GET form -> navigates with new scope. Works without client JS. */}
        <form method="get" action={pathname} className="scope">
          <label>
            env{" "}
            <select name="env" defaultValue={env}>
              <option value="live,beta">live + beta</option>
              <option value="live">live</option>
              <option value="beta">beta</option>
              <option value="dev">dev</option>
              <option value="live,beta,dev">all</option>
            </select>
          </label>
          <label>
            window{" "}
            <select name="days" defaultValue={days}>
              <option value="7">7d</option>
              <option value="14">14d</option>
              <option value="30">30d</option>
              <option value="90">90d</option>
            </select>
          </label>
          <button className="btn" type="submit">apply</button>
        </form>
        <form method="post" action="/api/logout">
          <button className="btn" type="submit">log out</button>
        </form>
      </div>
    </nav>
  );
}
