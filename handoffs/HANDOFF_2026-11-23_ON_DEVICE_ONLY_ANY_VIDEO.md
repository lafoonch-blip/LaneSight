# Handoff — On-device only, any video in, capture defaults + override (2026-11-23)

> **Amendments in INBOX.md (2026-11-23) override this brief where they differ:** next free DEC (likely DEC-133);
> Python reference engine stays the dev harness (Session 1's coverage work continues); in-app default stays
> 1080p120 SDR (Form floor 60) until the benchmark + gates pass; own worktree feat/capture-any-video.

**For:** Claude Code (repo `lafoonch-blip/LaneSight`). **From:** claude.ai discussion with Shayne, 2026-11-23.
**Run mode:** work straight through to the end and report once. Stop only for a real blocker or an irreversible action (live migration, push to main, deleting the production analysis service).

---

## 1. Context: what was discussed

1. **"Why 60 fps?"** The docs already default to the highest frame rate the phone supports (DEC-028, targeting 120; the cost review proposed 1080p120 SDR). 60 fps became the working baseline because of the server pipeline:
   - The cost of server analysis scales with the number of frames, and a 120 fps HDR clip (IMG_8831) cost about 3× as much and then failed.
   - The decode-once cache can't hold even one 1080p60 shot window (~3.3 GB).
   - Most validation (and the 1.12 rev factor) was measured at 60 fps.
   - Measured benefit of higher fps: rev precision is about ±40 rpm at 60, ±20 at 120 and ±10 at 240. Loft, axis and PAP need at least 120 fps. Speed and pins showed no gain. 4K showed no measured gain and costs about 3–4× more.
2. **Shayne: we've moved to on-device, so don't limit capture.** Agreed, with caveats:
   - Phones force a choice between resolution and fps (no 4K240), so the rule is: **max fps at ≥1080p, SDR, 4K when available at the same fps**.
   - Device load (heat, battery, memory) and low light at high fps are the real limits now.
   - Paired-fps validation is still needed.
3. **Shayne: drop the server fallback; one product, on-device measurement.** Any video type can be uploaded, and the app detects its quality and processes it. In-app recording has a default the user can change for more accuracy. Agreed, with one constraint: **retire server measurement per metric as each one ships on device.** Otherwise MVP metrics that are server-only today would disappear: strike/no-strike, laydown/launch angle, observed path, and all of Form.

---

## 2. Decisions to record (next free DEC)

Read the latest `00_CONTEXT/DECISIONS.md` first. If a newer DEC conflicts, follow the repo and note the conflict in the report.

**A. One product engine: on-device.**
- No server-fallback measurement in the product (amends DEC-102 and DEC-104's fallback-upload clause).
- Stop all new server-only CV/measurement work (extends DEC-117's freeze from speed/rev to all metrics). The Python reference engine remains the development/validation harness (see amendments).
- Retire the server measurement path **per metric** once that metric ships on device and passes its DEC-118 gate. When the last one ships, remove server analysis from the app flow: upload-for-analysis, `/jobs` analysis, and the Cloud Run analysis service.
- Unsupported phones show an honest "This iPhone isn't supported for analysis". The minimum is set from measured device capability (DEC-102), not the model name. Recording and saving still work on any phone.
- **Stays:**
  - The Python reference engine, as the dev/validation harness only (DEC-106).
  - The Supabase backend: auth, data, sync, and server-authoritative Score, tiers, achievements and coaching policy.
  - DEC-103 submission validation.
- Diagnostic clip retention (DEC-100) becomes opt-in upload of failed or flagged clips, with consent (DEC-104).

**B. Any video in (Upload).**
- On import, read the capture properties from the file:
  - real frame rate from presentation timestamps, including variable frame rate and iPhone slo-mo (use the native capture rate and real PTS, not the Photos slowed-playback edit);
  - resolution, orientation, dynamic range (SDR / HLG / Dolby Vision), codec and duration.
- Convert HDR to SDR on device with AVFoundation. DEC-113 showed that a mismatched HLG tone-map breaks ball tracking, so HDR gets its own validation set.
- Metric availability and precision follow the detected capture (DEC-028, DEC-023). Below the floor (30 fps / 720p, lane and pins in frame), the affected metrics are unavailable with a specific reason (e.g. "recorded at 24 fps, need 30+"), never estimated (DEC-026/027).

**C. In-app recording default + override.**
- **Default:** the highest fps at ≥1080p, SDR, with 4K when the phone offers it at the same fps; Form floors at 60. **Per the amendments, ship 1080p120 SDR as the default until item 12/16 gates pass at a higher format.**
- **Override:** Settings › Recording, plus a quick control on Setup, lists only the formats this phone supports, with plain-language trade-offs ("More detail for rev rate · larger files · more battery/heat").
- **Low-light guard:** if a high-fps capture is too dark or noisy, the result says so with a tip. It never silently changes format.

---

## 3. Work items

### 3.1 Record and sync
1. Add the DEC (next free number) to `00_CONTEXT/DECISIONS.md` and update the superseded list: DEC-102 fallback role, DEC-104 fallback upload, DEC-117 freeze scope, DEC-028/121 capture default.
2. Update `CURRENT_STATE.md`, `CLAUDE.md` / `AGENTS.md` (no server-fallback work), `01_PRODUCT/METRIC_CAPABILITIES.md` (tiers driven by detected capture) and `03_ENGINEERING/MVP_HANDOFF.md` where they describe the server fallback or the 60/120 default.
3. Update STATUS.md on the `context` branch and mark this INBOX item DONE.

### 3.2 Server retirement plan (no deletion yet)
4. Write `03_ENGINEERING/SERVER_MEASUREMENT_RETIREMENT.md` with one row per MVP metric (DEC-118):
   - columns: on-device status, gate status, server role today, retire-when condition;
   - include the order of removal for the app flow, the API and Cloud Run;
   - **do not** remove server analysis code or services in this pass.
5. Remove any in-progress server-only CV/perf tasks from the queue, and note them as withdrawn (DEC-116 leftovers, anything labeled server-speed).

### 3.3 iOS capture (default + override)
6. Recording format picker:
   - enumerate `AVCaptureDevice.formats` and build the supported (resolution, max fps, SDR) list;
   - default per §2C and the amendments;
   - force SDR (HDR off, 8-bit 420v/420f);
   - Form floors at 60;
   - persist the user's choice;
   - add Settings › Recording plus a Setup quick control. Add the screens to `APP_DESIGN_CHANGES.md` as NOT BUILT, with Figma first per DEC-091.
7. Record the chosen format and real PTS-derived fps on every shot (`capture_quality.capture` = width, height, fps_nominal, fps_measured, dynamic_range, codec, source=live).

### 3.4 iOS import (any video)
8. Import probe: read `AVAsset` / `AVAssetTrack` properties (`nominalFrameRate` and PTS-measured fps, `naturalSize` + `preferredTransform`, transfer function / HDR flags, codec, duration). For Photos slo-mo assets, read the original high-frame-rate track, not the slowed `AVComposition` playback. Store the same `capture_quality.capture` block with source=upload.
9. HDR→SDR conversion on device (AVFoundation / VideoToolbox, BT.2020 HLG/PQ → BT.709). Add HDR clips (IMG_8751, IMG_8754, IMG_8831) to the on-device validation set, and check ball tracking against the SDR baseline.
10. Capture-floor checks produce per-metric `unavailable` with reason codes, e.g. `CAPTURE_FPS_BELOW_MIN`, `CAPTURE_RES_BELOW_MIN`, `HDR_CONVERSION_FAILED`. Add them to `failures.py` / the iOS equivalent with user copy and tips.

### 3.5 Engine load at high fps / 4K
11. On-device engine runs each stage at a working resolution and frame rate:
    - detection/tracking may run on a downscaled or frame-reduced stream;
    - rev, release and pins read full detail.
    - Results must hold within metric tolerance against the full-rate run (DEC-094 promotion rule).
12. Measure on the target iPhone at 1080p60 / 1080p120 / 1080p240 / 4K60 / 4K120: time per shot, peak memory, battery drain and heat over a full ~30-shot session (DEC-106 gate C). Report against the DEC-118 <30 s gate.
13. Low-light check: brightness/noise metric on the trimmed window; below threshold, return a capture tip on the result.

### 3.6 Validation plan
14. Add a paired-fps capture set to `validation/`: CAPTURE_TEST_PLAN S1–S5 (1080p60 / 120 / 240 SDR, HDR on/off, 4K60/120) from the same position on the same day, with Specto where available (Ruby removed, DEC-105).
15. Re-validate the rev-rate factor at 120/240 (DEC-094 §4: blind-validate or remove).
16. Gate: a higher default is promoted only if DEC-118 Shot and Form gates hold at it; otherwise it stays 1080p120 SDR. Record that in the report.

---

## 4. Guardrails (unchanged)
- Honesty rules: never estimate a metric the capture can't support. Unavailable always comes with a reason (DEC-026/027/094).
- Every failed analysis gets a proactive root cause and a fix. Failed/flagged clips stay retrievable for a short window (opt-in upload under the new model).
- No AGPL models (DEC-094 §6). No audio-based measurement (DEC-132).
- Branch per task, push your own branch when gates pass, never push to main, never merge; Shayne merges.
- Don't apply live migrations or decommission Cloud Run in this pass. Only Session 1 deploys.

## 5. Report back (once, at the end)
- DEC number used, and the files changed.
- Retirement table (metric → on-device status → retire-when).
- Capture picker and import probe: what was built, which branch, Xcode build status.
- Device benchmark table by format.
- Open questions. Known ones:
  - minimum supported iPhone;
  - whether next-shot advice offline is still "show on reconnect" (DEC-106 open item);
  - consent wording for opt-in clip upload.
