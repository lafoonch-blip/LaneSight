import { Shell } from "@/components/Shell";
import { DataTable, type Column } from "@/components/DataTable";
import { Panel } from "@/components/State";
import { type SearchParams } from "@/lib/scope";
import { getStorageLatest, type StorageLatestRow } from "@/lib/queries";

export const dynamic = "force-dynamic";

// Human-readable bytes; null stays NO DATA (dash), never 0-as-fake.
function bytes(v: number | null): string {
  if (v === null || v === undefined) return "—";
  const u = ["B", "KB", "MB", "GB", "TB"];
  let n = Number(v), i = 0;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return `${n.toFixed(i === 0 ? 0 : 1)} ${u[i]}`;
}

export default async function Storage({ searchParams: _searchParams }: { searchParams: SearchParams }) {
  const latest = await getStorageLatest();

  const cols: Column<StorageLatestRow>[] = [
    { key: "bucket", label: "Bucket" },
    { key: "bytes", label: "Size", num: true, render: (r) => bytes(r.bytes) },
    { key: "objects", label: "Objects", num: true },
    { key: "aged_objects", label: "Aged (>TTL)", num: true },
    { key: "db_bytes", label: "DB size", num: true, render: (r) => bytes(r.db_bytes) },
    { key: "captured_at", label: "Snapshot", render: (r) => (r.captured_at ? new Date(r.captured_at).toISOString().slice(0, 16).replace("T", " ") : "—") },
  ];

  return (
    <Shell>
      <h1>Storage &amp; DB</h1>
      <p className="sub">Latest metering snapshot per bucket (DEC-098 M5).</p>
      <h2>Storage by bucket</h2>
      <p className="sub">
        Populated by the <code>ops_storage_snapshot</code> job. A bucket shows NO DATA until the job has run —
        sizes are measured, never estimated.
      </p>
      <Panel result={latest}><DataTable columns={cols} rows={latest.rows} /></Panel>
    </Shell>
  );
}
