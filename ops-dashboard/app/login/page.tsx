"use client";
import { Suspense, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabaseBrowser";
import { publicEnvReady } from "@/lib/env";

function LoginForm() {
  const router = useRouter();
  const sp = useSearchParams();
  const next = sp.get("next") || "/";
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const ready = publicEnvReady();

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      setError(error.message);
      setBusy(false);
      return;
    }
    // Session cookies are set by @supabase/ssr; middleware enforces owner-only on the next request.
    router.replace(next);
    router.refresh();
  }

  return (
    <div className="login">
      <h1>LaneSight Ops</h1>
      <p className="sub">Owner-only. Sign in with your LaneSight account.</p>
      {!ready ? (
        <p className="cfg">
          Not configured: set <code>NEXT_PUBLIC_SUPABASE_URL</code> and{" "}
          <code>NEXT_PUBLIC_SUPABASE_ANON_KEY</code> (see <code>.env.example</code>) and restart.
        </p>
      ) : (
        <form onSubmit={onSubmit}>
          {error ? <div className="err">{error}</div> : null}
          <input type="email" placeholder="Email" autoComplete="username" value={email}
                 onChange={(e) => setEmail(e.target.value)} required autoFocus />
          <input type="password" placeholder="Password" autoComplete="current-password" value={password}
                 onChange={(e) => setPassword(e.target.value)} required />
          <button className="btn" type="submit" style={{ width: "100%" }} disabled={busy}>
            {busy ? "Signing in…" : "Sign in"}
          </button>
        </form>
      )}
      <p className="note">Only the owner account can read the dashboard; any other sign-in gets 403.</p>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={<div className="login"><h1>LaneSight Ops</h1></div>}>
      <LoginForm />
    </Suspense>
  );
}
