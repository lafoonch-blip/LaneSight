# LaneSight handoff — DEC-131 form-upload fixes (on-device) (2026-11-17)

## Read first
Working dir **`~/Developer/LaneSight-form`** (NOT `~/Developer/LaneSight` — this is Session-2's tree; the venv editable maps to `LaneSight`, so run scripts with `PYTHONPATH=~/Developer/LaneSight-form/lanesight-core`). Read `AGENTS.md`, `00_CONTEXT/CURRENT_STATE.md`, last ~8 DECs in `00_CONTEXT/DECISIONS.md`.
Rules: don't deploy (Session 1 is the only deployer); push own feature branch when gates pass; ask before merge/migration/deploy. No mock/placeholder numbers.

## What's live right now
- **Cloud Run:** unchanged this session — **no deploy was done**. Server-side form changes (view classifier, delivery-isolation gate, bands, FORM_VERSION) are committed + pushed on `feat/form-ondevice` and ship with Session 1's next deploy.
- **Flags:** on-device-primary form path is default-ON in code (DEC-126, committed earlier `7d9b87a`).
- **Migrations applied to live:** none this session (no schema changes).
- **Device:** Release build with all 6 fixes **installed on Shayne's iPhone 17 Pro Max** (`00008150-000651C10138401C`, bundle `com.lanesight.app`).

## Branches (state of each)
- `feat/form-ondevice` @ `ff0350b` — DEC-131 form-upload fix batch (6 tasks). **pushed y** (verified `ls-remote` = `ff0350b1cce5115380d66f391127cc121f71f1ac` = local HEAD) · migration n/a · deployed **no** · merged **no**.
  - Commits this session: `c8af524` (task 2: delivery-isolation gate + bands), `ebbd38b` (tasks 1+5: view max(full,approach) + FORM_VERSION 1.0.0 + UI honesty), `ff0350b` (tasks 3/4/6: on-device thumbnails + offline shadow target + widen-on-truncation step recovery).

## What's done
All 6 tasks from the "two failed real form uploads" batch (b6cfd17c, ee17c156) — committed + pushed, gates green:
- **Task 1 — view:** both engines take **max(full-clip, approach-window) hip dy/dx** (full-clip alone is polluted by walk-around). Validated **9/9** (`lanesight-core/examples/form_view_window_probe.py`), no labeled-clip detected-view change.
- **Task 2 — delivery-isolation fail:** every window-derived timing/count → `unavailable` + `FORM_DELIVERY_NOT_ISOLATED` on both engines (never best_effort); physiological bands added for every P1 form metric (catches `backswing_height_rel −5.75`, pushaway `0.0`, etc.).
- **Task 3 — thumbnails:** E2/E3/E4/E7 stills extracted **on-device** from the local clip (`AppModel.extractFormKeyFrames`, `ShotResult.localKeyFrames`); UI shows them with no server fetch; server skeleton overlay suppressed on local full-frame stills.
- **Task 4 — server shadow:** verified it DOES run (DB: both uploads have a `platform=server` attempt w/ 70 metric + 70 stage outcomes); it's async (~min after the card). Closed the gap where an **offline** form upload never set a shadow target.
- **Task 5 — version/UI:** `FORM_VERSION` `form-0.0.0 → form-1.0.0` (both engines); header shows real version; timing-checkpoint verdict only shows when actually measured; swing bar degrades to "not measured".
- **Task 6 — step_count/E4/E7:** diagnosed (b6cfd17c first_step 15.76 vs 13.96 → 2 plants → banded; E4/E7 were fine. ee17c156 not isolated → withheld). Fix: widen-the-lead retry in `extractWindowed` (only fires when <3 plants, keeps wider only if strictly more steps → can't regress).

Verification done: **465 pytest pass**, **IMG_8751–54 regression PASS** (no shot-engine regression), **iOS Release build succeeds** + installed on device.
Ground-truth note: the two clip IDs are **swapped** vs their content — **b6cfd17c is REAR**, **ee17c156 is SIDE** (confirmed by delivery-frame inspection).

## What was running when stopped
Nothing. All background jobs (3 commit hooks + 2 pytest runs + the Release build/install) completed before stopping. Working tree **clean**. No training/eval in flight.

## Next round of work (do this)
1. **Validate on the re-upload (primary next step).** Shayne re-uploads the same two clips on the installed Release. Expect: **b6cfd17c → "Rear view"** with a real `step_count` (widen-on-truncation recovers the approach); **ee17c156 → "Side view"** with un-isolated timings shown `unavailable` (no −5.75); both show on-device key-position thumbnails; header reads `form-1.0.0`. The step fix + view fix are **device-pose-specific and could NOT be validated in Python** — this re-upload is the real test (see [[form-windowed-pose-coldstart]]).
2. **If step_count still truncates on b6cfd17c:** check the `+2.0 s` lead in `OnDeviceFormEngine.extractWindowed` is enough and that `deliveryProbe` re-pose fired — add a `FORM_PRESCAN_DBG` trace of the winner window + step counts.
3. **Server deploy of the form changes is Session 1's call** — do NOT deploy from here.

## Deferred / gated (don't start)
- No deploy, no merge to `dev-build-v0`/`main` (ask Shayne first).
- DEC-131 Phase 2 (on-device learned form engine to the 22-clip parity gate) is separate and not touched here.

## Watch out for
- **Clip-ID/label swap** (b6cfd17c=rear, ee17c156=side) — don't "re-fix" the view the wrong way.
- venv editable maps `lanesight_core` → `~/Developer/LaneSight` (Session 1's tree), so re-grading scripts need `PYTHONPATH=~/Developer/LaneSight-form/lanesight-core` ([[venv-editable-maps-to-lanesight-not-form]]).
- Pre-commit hook runs pytest + the slow IMG_8751–54 regression (~2–4 min); commits time out foreground — commit in background.
- Diagnostic scripts added under `lanesight-core/examples/`: `form_view_probe.py`, `form_view_window_probe.py`, `form_view_feat_probe.py`, `form_newclips_diag.py` (cached landmarks in `~/LaneSightData/form/lm_cache/`).

## Done-when
Re-upload of both clips on the installed Release shows the expected views + honest statuses + on-device thumbnails, and the server shadow attempt lands for each. Report the per-clip view, step_count, and whether any timing is shown that should be `unavailable`.

## How to restart anything that was killed
- Nothing was mid-run. To rebuild/reinstall Release if needed:
  ```
  cd ~/Developer/LaneSight-form/ios/LaneSight
  xcodebuild -project LaneSight.xcodeproj -scheme LaneSight -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath <dd> -allowProvisioningUpdates build
  xcrun devicectl device install app --device 00008150-000651C10138401C \
    <dd>/Build/Products/Release-iphoneos/LaneSight.app
  ```
- Re-run server tests: `cd ~/Developer/LaneSight-form/lanesight-core && source .venv/bin/activate && python -m pytest -q`.
