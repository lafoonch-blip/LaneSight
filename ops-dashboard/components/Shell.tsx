import { Suspense, type ReactNode } from "react";
import { Nav } from "./Nav";

export function Shell({ children }: { children: ReactNode }) {
  return (
    <>
      <Suspense fallback={<nav className="nav"><div className="nav-inner"><span className="brand">LaneSight Ops</span></div></nav>}>
        <Nav />
      </Suspense>
      <main className="wrap">{children}</main>
    </>
  );
}
