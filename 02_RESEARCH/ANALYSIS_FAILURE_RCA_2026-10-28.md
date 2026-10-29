# Analysis failure RCA: every logged attempt since attempt logging began
Status: ACTIVE · Version: 1.2 · Last Updated: 2026-10-28 · Owner: Shayne
Source: live `analysis_attempt` (the full table: 12 rows, 2026-10-27 16:14 → 2026-10-28 18:51 ET). Decision: DEC-100.

## 1. Scorecard
| Kind | Attempts | Usable result | Failure codes |
|---|---|---|---|
| Shot · upload | 6 | **0** | LANE_NOT_DETECTED_NO_EDGES ×2, FOUL_LINE_NOT_IN_VIEW, LANE_GEOMETRY_UNUSABLE, BALL_TRACK_NOT_FOUND, PIN_IMPACT_NOT_DETECTED |
| Shot · live | 3 | 2 | INTERNAL_ERROR ×1 (120 fps clip, 10-27 19:03) |
| Form · upload | 3 | **0 usable** | All 3 return status "analyzed". But the two from 10-28 have **every swing event dropped** (no key positions, timing checkpoints all unavailable). |

**An uploaded Shot clip has never produced a result.** Live shots work about 2 times in 3. Form "succeeds" but returns an empty card.

## 2. Findings from the data (no clips needed)
1. **Tonight's uploads were re-uploads of yesterday's failures, with identical bytes and identical results.**
   - Shot 18:51 = shot 10-27 18:13: same 8,177,981 bytes, same 2.82 s, same LANE_NOT_DETECTED_NO_EDGES.
   - Form 18:50 (rear) = 10-27 18:15: same 21,922,842 bytes. Yesterday that clip ran as **Shot** and failed LANE_GEOMETRY_UNUSABLE, which means a form clip went through the ball CV.
   - The engine is deterministic and nothing changed for these failure modes, so the "worse" success rate is the same failures repeating. Nothing tonight was a new regression.
   - Upload duplicate detection is paused (DEC-086), so repeats are re-analyzed rather than flagged.
2. **Clip retention was off, so no failure could be reproduced.** `analyze_from_storage` deleted the clip right after analysis; `LANESIGHT_KEEP_CLIPS` was dropped at rev 00030. **Fixed (DEC-100):** clips are retained 7 days (newest 40 per user), and `clip.storage_path` is written on the attempt row. `ops/fetch_clip.py` pulls the clips and re-runs them.
3. **Phone-side failures were invisible.** Shayne made 4–5 attempts tonight; 3 reached the server. A trim, upload or dropped-request failure left no record. **Fixed (DEC-100):** the app posts `/analysis/client-failure` (stage + error + clip bytes) into `analysis_attempt` as `CLIENT_<STAGE>`.
4. **Phone trim produces very short upload clips.** The failing 2.82 s shot clip came out of a 13 s trim pass (the motion-window trim). The original was much longer. The server never saw the pre-trim frames. If the trim window starts after the ball crosses the foul line, the foul line and lane start are missing → FOUL_LINE_NOT_IN_VIEW / LANE_NOT_DETECTED. **Hypothesis H1.** Test by running the original vs the trimmed clip.
5. **Successful live shots differ from every failed upload in framing.**
   - Both successful live shots: 1440×1080 (4:3), about 25 s, the full shot window.
   - Every failed upload: 1920×1080 rotated (portrait 16:9). Either the clip was very short after the trim, or it was very long and the trim didn't cut it (72.7 s at 30 fps → only 3 track points; 22.6 s → pins not found).
   - **Hypothesis H2:** the upload source (Photos portrait 16:9, often 30 fps) is outside what the lane detector was validated on (DEC-062 validation clips).
6. **Form: the DEC-095 gate drops whole deliveries.**
   - Both 10-28 form clips measured ball-start→release at **1.135 s and 1.185 s**. DEC-095 requires 1.3–2.5 s, so it dropped every display event, even though `swing_time` still shows as best effort.
   - Both clips also detected only **3 steps** (`first_step` at 3.3 s and 1.3 s).
   - **Hypothesis H3:** the start of the approach is missing (trimmed by the phone, or out of frame). The detected "ball start" is late, so the swing reads short and fails the gate.
   - **Hypothesis H4:** the 1.3 s floor is too strict for some bowlers. Either way, a gated delivery must be reported as a coded failure with a reason, never as "analyzed" with an empty card.
7. **The Shot/Form choice can't be verified from the clip.**
   - A side-view form clip was analyzed as Shot (finding 1).
   - Since DEC-099 the mode is picked up front. But the server never checks that the clip matches the mode: Form Analysis detects the camera view (DEC-076), and nothing stops a form clip going through the ball CV.

## 2a. Shipped on `fix/clip-retention-diagnostics` (deploy pending)
- Clips retained 7 days and linked to the attempt; `ops/fetch_clip.py`.
- Each failed attempt stores 4 snapshot frames (`clip.frames`), viewable from the database.
- Phone timings record `orig_duration_s` / `upload_duration_s` / `orig_bytes`. These test H1 on the next failure without the original clip.
- Phone-side failures are logged (`CLIENT_<STAGE>`).
- Form: a fully gated delivery fails as `FORM_DELIVERY_NOT_ISOLATED` (with the gate numbers) instead of an empty card. Form clips are no longer motion-trimmed (H3).
- Originals of the 10-27/10-28 clips aren't available. E1–E3 run on the **next failing uploads** instead, using the retained clip + frames + trim durations.

## 3. Root-cause experiments (run on the Mac, where the clips and validation set live)
Run these in order. Each one must report numbers.

| # | Experiment | Confirms / rules out |
|---|---|---|
| E1 | Shayne exports the originals of the 4 failing upload clips from Photos (the 2.82 s shot, the 72.7 s, the 22.6 s, the rear-form clip) → `~/LaneSightData/diagnostics/2026-10-28/`. Run the pipeline on **original vs `VideoTrimmer` output**. | H1 (trim cuts the lane start) |
| E2 | On originals that still fail: dump frame 0 + the lane mask (`find_lanes`) + precheck keyframes. Classify each as framing (lane not in view or angle) vs detector (lane visible but missed). | H2 |
| E3 | Form: run both 10-28 form originals untrimmed; report events E2–E8, step count and swing time vs the DEC-095 window. | H3 vs H4 |
| E4 | Re-run the 10-27 19:03 live INTERNAL_ERROR (if the clip is in `~/LaneSightData/sessions`) on the current engine (DEC-093 crash guard). | Whether INTERNAL_ERROR is already fixed |
| E5 | For every fix: re-run the DEC-062 validation clips (IMG_8751–8754) and the DEC-092 benchmark, and report before/after. No unvalidated CV change ships. | Regression gate |

## 4. Fix order (pending E1–E3)
1. **If H1:** trim must keep the foul line and the approach. Use a pre-roll of ≥1.5 s before motion onset, or upload untrimmed when under the size cap. Form clips: never trim the head.
2. **Gated form delivery → coded failure** (e.g. `FORM_DELIVERY_NOT_ISOLATED`) with the friendly reason and the gate value, so the app says "Couldn't analyze" plus a tip instead of showing an empty card.
3. **Mode/clip mismatch check:** a fast server-side view check. A side/rear bowler clip sent as Shot (or a lane-only clip sent as Form) gets a coded failure that tells the user to switch mode.
4. **H2 / framing:** upload-time guidance (show the precheck verdict before the full analysis), then detector work under DEC-094 (shadow, accuracy-gated).
5. Track the success rate daily from `analysis_attempt` (ops dashboard, DEC-098), split by mode × source, including the `CLIENT_*` rows.


## 5. Evening run (20:45–21:35 ET, 5 uploads, rev 00036): findings
**Process failure first.** Rev 00036 was deployed from `dev-build-v0` (ops instrumentation), which has neither DEC-099 nor DEC-100 server code. So no clips were retained and no snapshot frames were saved, and the Form gate change didn't run. The **iOS** build did have DEC-100, so the phone's trim numbers were recorded. Fix: `integrate/dec-099-100-with-ops` merges both lines (368 tests pass). Deploy from it only.

| Time | Mode | Phone: original → uploaded | Result | Root cause |
|---|---|---|---|---|
| 20:45 | Shot | 21.8 s → 13.3 s (lossless trim) | TRACK_TOO_SPARSE_FOR_SPEED: 3 on-lane ball points, 1 in 4–24 ft | **Ball detection density** (DEC-094 3b). The trim kept the shot. Needs the retained clip to see why. |
| 20:51 | Shot | 26.1 s → 26.1 s (re-encoded 75.9→45.6 MB to fit the cap) | BALL_TRACK_NOT_FOUND: 0 points | Unknown (no clip). Candidates: wrong lane picked in a multi-lane view (DEC-093, IMG_8929 pattern), or the re-encode. |
| 20:55 | Form | 30.3 s → 30.3 s (not trimmed: DEC-100 phone change worked) | "analyzed", but empty: swing 0.57 s, slide stop (E8) *before* slide start (E5), no key frames | **Delivery mis-isolated by the pose engine** (DEC-095's open root cause). On this server it still showed as an empty card; with DEC-100 it fails as FORM_DELIVERY_NOT_ISOLATED. |
| 21:33 | Shot | 19.3 s → **3.3 s** | Analyzed, far lane limited (late speed > early speed) | The trim cut the clip near the pins → far-lane read unreliable (likely). |
| 21:35 | Shot | 17.1 s → **2.85 s** | PIN_IMPACT_NOT_DETECTED: 121 ball points, track ends at 2.74 s of 2.97 s | **CONFIRMED: the phone trim cut the clip before the ball reached the pins.** |

**H1 confirmed for the tail, not the head.** `VideoTrimmer`'s motion window ends when the near-camera motion stops (the bowler), while the ball is still rolling far away (low pixel motion at 160 px), plus a 0.4 s pad. This also explains 10-27/10-28's 2.82 s clip (FOUL_LINE_NOT_IN_VIEW / LANE_NOT_DETECTED): it was cut to a ~3 s window.

**Fix shipped (DEC-101, iOS):** the Shot trim now cuts only the dead time before motion (keeps 1 s before onset) and always keeps ≥10 s after onset. Form clips are never window-trimmed. The re-encode-to-fit path is unchanged (bitrate only); watch whether re-encoded clips track worse (20:51).

**Next, on the first failures after the deploy** (retained clip + frames):
- 20:45-type sparse tracks → detection-density work (DEC-094 3b, shadow).
- 20:51-type zero-point tracks → check the chosen lane (`capture_quality.lane`) and the re-encode.
- Form mis-isolation → run the pose events on the retained clip and fix the delivery-window selection (DEC-095).
