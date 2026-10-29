# Offline-first local store + sync — spec (OD-02 / OD-03)
Status: DRAFT + first increment on `feat/on-device-analysis` · 2026-10-29 · DEC-102/103
Proposal §5.2, §6.6. Keeps DEC-068/080 (online = blocking Analyzing screen → shot details, unchanged).

## Persistence choice — justification (first increment: file-based, not SwiftData/GRDB)
The store is a **cache + outbox**, append-mostly, with the server as the source of truth — not a second
authoritative DB. For that shape the first increment is a **dependency-free, file-based JSON store** (one file
per record under an account-scoped Application Support dir, written with `.completeFileProtection`):
- **No new dependency** (proposal risk #11: app-size/deps). No SPM package.
- **Encrypted at rest** via `NSFileProtectionComplete` → satisfies the §6.6 minimum with no crypto layer.
- **No Swift-6 `ModelContext` concurrency surprises** — the whole store is `@MainActor`, trivially correct,
  and durable across app kill (it's just files).
- **Rejected for now:** SwiftData / GRDB. SwiftData's `ModelContext` is not `Sendable` and complicates the
  background-sync actor; GRDB is an SPM dependency. Revisit either **only if** rich local querying is needed
  (e.g. offline Stats over many sessions) — the file store is the right call for an outbox.

Implemented in `ios/LaneSight/Sources/Offline/OfflineStore.swift` (compiles + installed; not yet wired in).

## Data model (local cache + outbox)
Account-scoped: every record carries `accountRef` (the signed-in user id); a sign-out/delete purges all rows
for that account (§6.6). All sync records carry a **client UUID** and an **idempotency key**.

```
LocalSession   { id(clientUUID), accountRef, startedAt, mode, lane, oilPatternId, endedAt?, serverId?, rev }
LocalShot      { id(clientUUID), accountRef, sessionId?, capturedAt, source, captureMode,
                 localClipPath?, state: pending|analyzing|analyzed|failed, serverShotId?,
                 resultJSON?, engineVersion?, idempotencyKey, rev }
OutboxItem     { id, accountRef, kind: analyze|sessionCreate|sessionEnd|profile|arsenal,
                 payloadJSON, idempotencyKey, createdAt, attempts, nextAttemptAt, state: pending|inflight|done|dead }
```

- **Immutable / revisioned:** `LocalSession` and `LocalShot` measurement results are never overwritten; a
  re-sync updates `serverId`/`state` only. Arsenal changes are revisioned (`rev`++) so history is kept (DEC-007/044).
- **Last-write-wins:** only simple profile scalars (name, handed, units).

## Sync protocol (outbox drain)
1. Every user action that needs the server (create session, analyze a clip, end session, profile/arsenal edit)
   writes a local record **and** an `OutboxItem` in one transaction, with a fresh `idempotencyKey`.
2. A `SyncEngine` actor drains the outbox when connectivity is up (NWPathMonitor) and on app foreground.
   Per item: POST with `Idempotency-Key` header; on 2xx mark `done` + patch the local record with the server id;
   on 5xx/timeout increment `attempts`, set `nextAttemptAt` with exponential backoff (cap ~5 min); on 4xx
   (validation) mark `dead` and surface it (never silently drop).
3. **Survives app kill:** the outbox is on disk; drain resumes on next launch. Nothing lives only in memory.
4. **No duplicates:** the server dedupes by `Idempotency-Key` (see server half below). A resend after a dropped
   response returns the original result, never a second analysis.

## Server half (OD-02A) — idempotency keys
The server already dedupes *uploads* by `content_hash` (`find_upload_by_hash`). Generalize, don't fork:
- Accept an `Idempotency-Key` header on the mutating analyze/session endpoints.
- Store `(user_id, idempotency_key) → shot_id/session_id` (small table, additive migration). A repeat key
  returns the stored result (same shape as the content-hash dedupe path) with `duplicate: true`.
- `content_hash` dedupe stays as a second safety net for identical bytes; the idempotency key covers the
  "same logical action, retried" case (different bytes not required).

## Offline UX (OD-03) — keeps DEC-068/080
| Situation | Behavior |
|---|---|
| Online | **Unchanged.** Blocking Analyzing screen → shot details (DEC-068/080). |
| Offline, record a shot | Save a `pending` `LocalShot`; return to the Active Session with an **"Analysis pending"** row (styled like "Couldn't analyze", DEC-096). No blocking screen. |
| Shot card for a pending shot | "Advice when you're back online." No fabricated metrics (DEC-026/061). |
| Score / Home offline | Show the **last stored** score + "latest session not yet included". **Never** a locally-computed score (DEC-039/051/072). |
| Connectivity banner | Non-blocking; never gates navigation. |
| Advice chip | Provisional / Low confidence / Ready (server-decided; §5.4). |
| Resume session | Works from the local store after relaunch (DEC-096). |

Every screen that differs from Figma "Target state – v3.7" gets a row in `APP_DESIGN_CHANGES.md` (DEC-091).

## Acceptance (OD-02A) — must be verified ON DEVICE by Shayne
1. Airplane mode: record → "Analysis pending" → reconnect → analyzed **once** (no duplicate attempt row).
2. Force-quit mid-sync → relaunch → outbox resumes, still no duplicate.
3. Account switch: user A's pending shots never appear for user B.
4. Sign-out / delete: local store purged for that account.
5. Storage-full: enqueue fails safe (surfaced, not a crash).
6. Every synced record carries an engine version.
These need physical network toggling + two accounts, so they are **Shayne-run**; Swift unit tests cover the
outbox state machine + idempotency-key generation headlessly.

## Build increment on this branch (what's actually coded)
See `ios/LaneSight/Sources/Offline/` — SwiftData models + `OfflineStore` + `SyncEngine` skeleton that compiles
and installs. **Not yet wired into `AppModel.runPipeline`** (that wiring + the device acceptance run is the next
step, gated on Shayne's airplane-mode verification). Nothing offline is authoritative; the server stays the
source of truth.
