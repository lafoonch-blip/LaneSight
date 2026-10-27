# MVP Engineering Review — concerns before the rebuild
Status: FOR SHAYNE · Version: 1.1 · Last Updated: 2026-10-26 · Owner: Claude Code
Scope: the target-state v3.7 designs + MVP_HANDOFF v1.0 vetted against the **actual** backend on `dev-build-v0`
(Cloud Run + Supabase, as deployed 2026-10-26). Purpose: surface risks/gaps before any code is written.
Not a plan — a risk list. Per-phase plans come after you've reacted to this.

## 0. Bottom line
The spec is strong and most of the engine/API already exists (see §1). The MVP is **not** mostly-new code — it's
a handful of new read-endpoints + response fields on top of working engines. The real risks are **not** in the
screen build; they're in four places: (1) whether the bowling-center camera can produce the far-lane numbers the
whole Shot card + score depend on, (2) Form's cloud + capture dependencies, (3) Cloud Run's ephemeral disk vs.
the images the UI serves, and (4) the synchronous backend vs. the resilience the MVP flows assume. Ranked below.

## 1. What already exists (so we don't re-plan it)
- **Engines run end-to-end:** `after_shot_analyzed`, `at_session_end`, `recompute_score` (L-dev-0), `run_achievements`,
  `evaluate_tiers`. Validated this session: staged `active` scored 777/Platinum through the live cloud.
- **Endpoints present:** score, score/history, activity, stats, sessions (+end), shots (+analyze, +pins, +frame/{key}),
  uploads (+signed-url), spot-check, achievements, notifications, arsenal, oil-patterns, feedback, profile, avatar.
- **Form pipeline exists** (`lanesight_core/form/`: analyze, pose, fundamentals, spotcheck). `KEY_FRAME_EVENTS` is
  already `ball_start / end_pushaway / top_of_swing / release` — exactly MVP-01, `finish` already dropped (DEC-082).
- **Status chips** (MEASURED/BEST EFFORT/UNAVAILABLE) are in the measurement model (DEC-061).
- Migrations through 018; form fundamentals (015), content-hash dedupe (016), avatar/location (017) all in.

## 2. Concerns, ranked

### C1 — CRITICAL: the Shot card and the score's biggest pillar depend on far-lane geometry the bowling-center camera may not deliver
- **Design assumes:** Shot card shows strike/pocket, entry board, entry angle, breakpoint, "next move"; the score's
  performance pillar S′ = `0.6·pocket% + 0.4·angle%` where pocket% = entry board 16–19 and angle% = entry angle 4–6°.
  All of these are **far-lane** metrics.
- **Reality (Phase-1 CV verdict + DEC-065):** from an elevated ball-return camera the far-lane depth scale is
  unreliable; the pipeline **correctly gates those metrics to UNAVAILABLE** rather than fake them. Only near-field is
  solid from a bad position.
- **Impact:** if testers film from a convenient-but-wrong spot, the Shot card's *headline* result, the *next move*,
  **and** the performance pillar of the score all collapse to UNAVAILABLE. The designs anticipate this ("UNAVAILABLE
  + camera tip, no move") — but if it's the *common* case, the app mostly shows camera tips, not insights.
- **Needed before the MVP delivers value:** a validated **capture position** + in-app guidance that yields valid
  far-lane geometry (this is the Phase-1 recommendation, not ML). Decide this before wide testing; otherwise most
  shots return "move your camera."

### C2 — CRITICAL/INFRA: Form (a whole MVP flow) does not run in the cloud yet, and has a capture-quality floor
- **Design assumes:** Form session flow, Form results (key positions + skeleton + measurements), Stats › Form.
- **Reality:** the Cloud Run image **deliberately omits mediapipe + the 29 MB pose model** (Dockerfile note) to keep
  the first deploy small. Form code exists but **cannot execute in the cloud**. Separately, the Form pilot (§9 of
  FORM_ANALYSIS_SPEC) *failed* on generic pose when the bowler was small in frame; most Form metrics need **side
  view, bowler ≥40% of frame, 120 fps**.
- **Impact:** Form is blocked twice — infra (model not deployed) and capture quality (position/fps/size). A Photos
  upload at 30/60 fps or a small bowler yields mostly UNAVAILABLE.
- **Needed:** (a) a Form-enabled image (`.[api,form]` + model on the image or a bucket) + the processing-time/RAM
  re-benchmark on Cloud Run; (b) the same capture-guidance discipline as C1, for Form.

### C3 — HIGH: Cloud Run's ephemeral disk loses the images the UI serves (key positions + avatars)
- **Design assumes:** Form results show key-position **thumbnails**, tap → **full frame** with skeleton; profile shows
  an avatar.
- **Reality:** `/shots/{id}/frame/{key}` serves `DATA_ROOT/out/{shot_id}_form_{key}.jpg` and the avatar serves
  `DATA_ROOT/avatars/{user}.jpg` — **both from local disk via FileResponse**. Cloud Run `/tmp` is ephemeral and the
  instance scales to zero, so these files **disappear** when the instance recycles.
- **Impact:** key-position images (the heart of the Form results screen) and avatars break after the first scale-down
  — intermittently, which is the worst kind of bug to diagnose in the field.
- **Needed:** store key-position JPEGs + avatars in **Supabase Storage** (we already stand up Storage for clips;
  migration 017 anticipates avatars there). Plus a retention decision (MVP §5): keep images with the shot record?
  This is the same root cause as the deferred "avatars → Storage" item — it's now load-bearing for Form, not cosmetic.

### C4 — HIGH: the synchronous backend undercuts the resilience MVP-10/MVP-11 promise
- **Design assumes:** MVP-11 Analyzing screen keeps the screen awake and **auto-opens results**; MVP-10 a failed
  upload stays on the phone, retries automatically, **survives app restart**.
- **Reality:** Phase-1 runs CV **inline in one long HTTP request** (90–330 s). "Auto-open results" works only while the
  app sits on the Analyzing screen for the whole request. If the user backgrounds the app or the bowling-center
  connection drops, the app sees "failed" even though the result may have **completed and saved** server-side.
  Re-sending an *upload* is safe (dedupe); re-sending a *live shot* duplicates.
- **Impact:** MVP-10/MVP-11 acceptance ("survives restart", "auto-open") is **not fully achievable** on the synchronous
  model. This is the durable-`analysis_jobs` follow-up we deferred — flagging that two MVP items quietly depend on it.
- **Needed (when you un-defer it):** a durable job/result record keyed by a client idempotency key, so the app recovers
  a result by polling instead of failing, and a live-shot retry is de-duplicated too.

### C5 — MEDIUM: the score and "vs your typical" will show "building" for a long time
- **Design assumes:** Home score, Session summary "vs your typical".
- **Reality:** score eligibility floors are **20 / 20 / 10 / 10** comparable shots (S′/A/C/P′), where *comparable* =
  **same ball config + same intended target line**; "vs your typical" needs **≥3 comparable sessions**; Accuracy needs
  a **target line set** at setup or it's "—", never 0.
- **Impact:** a new tester sees "Building your score" and empty "vs typical" for many sessions, and sees no Accuracy at
  all unless they set targets. Correct and honest (the designs have building states) — but set expectations, and
  confirm the floors are realistic for the few-session testing window (they may be tuned for a season, not a demo).

### C6 — MEDIUM: new API surface to build (small, but enumerated so nothing is missed)
Buildable on existing engines; mapping MVP_HANDOFF §2–3 to what's missing today:
- **New endpoints:** `/me/focus` (MVP-12), `/me/last-setup` (MVP-09), `/me/stats/metric/{metric}` (MVP-08),
  `/sessions/{id}/summary` incl. `typical` (MVP-07). (`/sessions/{id}/end` exists and returns a summary today — decide
  whether summary is a separate GET or stays on `end`.)
- **New response fields:** `eligibility` on `/me/score` (per-part progress for the building UI); `insights.expected`
  (the "expected effect" text — `insights` already carry `reason`/`evidence`, so `why` is largely there, `expected`
  is new); `key_positions[]` on form `/shots/{id}`.
- **Verify, don't assume:** whether `/me/score` already exposes per-part eligibility progress, and whether the
  recommendation engine already emits an "expected effect" or only `reason`/`evidence`.

### C7 — MEDIUM: one analysis at a time, globally
- `--concurrency 1 --max-instances 1` (confirmed). Two simultaneous uploads → the second waits behind a 90–330 s
  analysis and can hit the 600 s client timeout. You've deferred this until after redesign/testing — fine for solo
  testing, but it's a hard wall the moment two friends bowl at once, and Form (mediapipe) will push analysis time up.

### C8 — LOW / verify during planning
- **Status-chip taxonomy:** confirm the measurement `status` values map cleanly to exactly 3 chips and that every
  UNAVAILABLE carries a reason string (the UI never shows a number without a chip, never a number when UNAVAILABLE).
- **P′ reference ranges:** the power pillar normalizes against owner-editable `engine_config` ranges (seeded live this
  session). Sanity-check the values against real data before trusting the P′ contribution.
- **Rev rate fps dependence:** rev is BEST EFFORT and excluded from Consistency when its ±band > 30 rpm (e.g. ~±40 at
  60 fps). Photos uploads at 30/60 fps will often drop rev from the score — expected, but it thins coverage.

## 3. Decisions this review needs from you
From MVP_HANDOFF §5 (restated) + surfaced here:
1. **Capture position** for Shot (C1) and Form (C2) — the single biggest determinant of whether the MVP shows
   insights or camera tips. Validate a position before wide testing.
2. **Pose model + confidence threshold** for Form overlays (handoff suggests MediaPipe Pose heavy, visibility ≥ 0.5)
   — and getting it into the Cloud Run image (C2).
3. **Image storage + retention** for key positions + avatars → Supabase Storage (C3); keep images with the shot record?
4. **Scope of durable jobs** for this MVP (C4): accept MVP-10/11 as "best effort on a good connection" now, or build
   the durable-jobs record first.
5. **Score floors** (C5): keep 20/20/10/10 for testing, or a lower "demo" floor so testers see a score sooner?

## 4. Suggested sequencing (before screens)
1. Resolve **capture position** (C1/C2) — it gates whether any of the headline UI has data.
2. **Form-enable the cloud image** + re-benchmark (C2), and move **key-position + avatar images to Storage** (C3)
   — these are infra, independent of the screen work, and block the Form flow.
3. Build the **new read-endpoints + response fields** (C6) on the existing engines; verify eligibility/expected.
4. Decide durable-jobs scope (C4) — at least make live-shot retries idempotent to avoid duplicates.
5. Then the screen rebuild from Figma, with C7 (concurrency) revisited when more than one tester is live.

## 5. Progress + new findings (2026-10-26, from executing the above)
Done and validated on Cloud Run (rev 00005):
- **C3a avatars → Storage** — PUT/GET/DELETE use the private `shot-images` bucket; round-trip validated on live
  Storage. (commit 4fedaf8)
- **C2 Form in the cloud** — image builds with mediapipe + the sha-pinned heavy pose model; needed two Linux
  libs the first build missed (`libgl1`, then `libegl1`+`libgles2` — mediapipe opens an EGL/GLES context even on
  CPU; found via an end-to-end cloud failure). Form clip analyzed in the cloud: 126 s on 4 vCPU, 11 metrics,
  4 key frames. Peak RAM locally 1.62 GB (4 GiB fine). (commits a325753, b924c7c)
- **C3b key-position frames → Storage** — uploaded after analysis; GET /shots/{id}/frame/{key} serves from
  Storage; all 4 frames returned HTTP 200 in the cloud. (a325753)
- **C4 partial — live-shot retry idempotency** — content-hash dedup extended to live shots (session-scoped);
  committed, not yet deployed (no retrying client until the iOS rebuild). (53ce9b3)
- **C1 capture guidance** — drafted (`02_RESEARCH/MVP_CAPTURE_GUIDANCE.md`); pending field validation.

Corrections / new findings:
- **C6 eligibility ALREADY EXISTS.** `/me/score` already returns `eligibility` {part:{have,need,met}} live — the
  review listed it as new. The remaining C6 endpoints (`/me/last-setup`, `/me/focus`, `/me/stats/metric/{m}`,
  `/sessions/{id}/summary`+typical, `insights.expected`, structured `key_positions[]`) are genuinely new and are
  **best built against the Figma contract** (exact per-screen fields), i.e. with the rebuild — not speculatively.
- **C9 — NEW DECISION: Supabase free tier caps Storage uploads at ~50 MB per file.** A 43 MB clip uploads; 61 MB
  (a full 120 fps Form clip) is rejected (413 EntityTooLarge) regardless of the bucket's own limit. So full-size
  clips — especially Form (120 fps) and untrimmed Shot — can't upload on the free plan. Options: (a) **trim/
  compress on-device before upload** (free; aligns with the trimming goal; a trimmed delivery fits easily — a
  tight ~11 s Form trim was 23 MB); (b) resumable/TUS upload (verify it bypasses the free cap); (c) Supabase Pro
  (~$25/mo, 50 GB). Recommend (a). This gates whether large clips work at the bowling center.
- **MVP-03 view classifier not auto-detecting.** Form on the canonical side clip (IMG_8905) returns
  `view=unknown`, so view-specific metric gating can't apply. The pose pipeline still produced 11 metrics; view
  detection is its own MVP-03 work item.
- **Follow-up (pre-existing): dedup can return a FAILED shot.** `find_upload_by_hash`/`find_shot_by_hash` match any
  shot with the content hash, including one whose analysis failed (empty record) — so re-uploading a clip that
  failed returns the failure instead of retrying. Fix: only dedup to a successfully-analyzed shot (persist a
  success marker — PgStore.save_shot_result doesn't currently write the `result` column — and filter on it).
