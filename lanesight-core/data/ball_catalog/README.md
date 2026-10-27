# Ball catalog (ball-catalog-1.0)

**2,288 balls:** every major brand's current lineup (211, as of 2026-10-21) plus **2,077 retired balls** (added 2026-10-27, DEC-084), so bowlers can find the balls they actually own.

Current lineups: Storm (42), Roto Grip (16), 900 Global (5), Brunswick (50), DV8 (6), Radical (13), Hammer (36), Ebonite (10), Track (7), Motiv (26). Columbia 300 has no current balls (Brunswick retired the brand in 2026).

Feeds the shared `ball_models` table (DEC-007) used by the arsenal (`user_balls` → `ball_models`) and by recommendations.

## Files
| Path | What |
|---|---|
| `raw/<brand>.json` | Collected records, one per ball, exactly as sourced (`RECORD_SPEC` fields). Edit these, never the outputs. |
| `catalog.json` | Generated: validated records + normalized reaction. |
| `lanesight_core/models/migrations/002_ball_catalog.sql` | Adds photo, specs, ratings and normalized-reaction columns to `ball_models`; read-only RLS for signed-in users. |
| `lanesight_core/models/seed_ball_catalog.sql` | Generated idempotent upsert keyed on (manufacturer, name). |
| `lanesight_core/models/migrations/003_ball_configuration_surface.sql` | Pin buffer and pin up/down on layouts; structured grit/polish on surface events; `shots.surface_event_id`; `user_ball_current` view; owner-only RLS on layouts and surface events. |

Rebuild after editing `raw/`:
```
python -m lanesight_core.arsenal.build_seed data/ball_catalog/raw \
  --out data/ball_catalog/catalog.json --sql lanesight_core/models/seed_ball_catalog.sql
```
Invalid records are rejected and listed, never patched.

## What each ball carries
- **Stock photo:** `image_url` links the manufacturer's own product image (Motiv: bowling.com image, `image_source: retailer`). Linked, not hosted — get manufacturer permission before copying images into Supabase Storage. All 210 URLs returned an image on 2026-10-21; Motiv Covert VIP EXJ has none published.
- **Out-of-box specs (15 lb):** cover/coverstock, core name and type, RG, differential, intermediate differential (Storm "PSA", Brunswick-family "ASY"), factory finish, stated oil condition, line and tier. Unpublished values are `null` and named in `missing`; `spec_source_urls` cites every page used.
- **Published ratings, untouched:** `mfr_ratings` (manufacturer), `retailer_ratings` (bowling.com), `motion_chart` (Brunswick Ball Motion Comparison Chart, Oct–Nov 2026).
- **Expected reaction, normalized** for cross-brand recommendations:

| Field | Scale |
|---|---|
| `ls_hook` | 1 little hook … 10 maximum |
| `ls_length` | 1 reads very early … 10 very long |
| `ls_backend` | 1 smooth/arcing … 10 angular |
| `ls_oil`, `ls_oil_min`, `ls_oil_max` | dry · light · medium · medium_heavy · heavy |
| `reaction_shape` | straight · arc · continuous · angular · skid_flip |

`reaction_basis` records the source of each value; `reaction_confidence` is high (hook and length both from published numbers), medium (at least one published) or low (estimated from specs only).

## Where the reaction numbers come from (priority order)
1. **Brunswick motion chart** (oil 1–16, shape 1–18) — one chart across Brunswick, DV8, Radical, Hammer, Ebonite, Track. Agrees with bowling.com hook labels (r = 0.78, n = 36) and with manufacturers' stated oil (r = 0.81, n = 61).
2. **bowling.com numbers**, only when inside the page's own stated scale. Its numbers are inconsistent (DV8 hook 325 with no scale; TZone shown on 10–175 and 10–250), so out-of-scale values are ignored.
3. **Manufacturer numbers** on a stated scale (Storm Hook Length / Ball Shape sliders, 1–11).
4. **Manufacturer numbers without a stated scale** — Motiv's 0–100 reaction bars (its spare reads 100/0/0). Basis `mfr_rating_inferred_scale`.
5. **Word ratings** (e.g. "High", "Early to Mid") — ranges are averaged.
6. **Spec estimate** from cover type, RG, differential, finish and core — always `low` confidence; the UI must label it.

Colorways of the same ball (same cover, core, finish, RG, diff) share published ratings; the record notes the donor colorway.

| Basis for `ls_hook` | Balls |
|---|---|
| Brunswick motion chart | 61 |
| Word rating | 80 |
| Motiv chart (inferred scale) | 25 |
| bowling.com number | 8 |
| Spec estimate | 37 |

Confidence: 34 high, 150 medium, 27 low.

## Retired balls (added 2026-10-27, DEC-084)
`status = 'discontinued'`, `discontinued_on` null (the retirement date isn't published). Collected with `backfill/` (see the scripts' docstrings); the weekly refresh carries them over like any other record and revives one if a brand re-lists it.

| Brand | Retired balls | Source | 15 lb RG/diff | Photo | Release date |
|---|---|---|---|---|---|
| Storm | 569 | bowwwl.com | 569 | – | 569 |
| Roto Grip | 232 | bowwwl.com | 232 | – | 232 |
| 900 Global | 140 | bowwwl.com | 140 | – | 140 |
| Motiv | 162 | bowwwl.com | 162 | – | 162 |
| Brunswick | 197 | brunswickbowling.com retired pages | 171 | 197 | 26 |
| DV8 | 122 | dv8bowling.com retired pages | 85 | 122 | 22 |
| Radical | 118 | radicalbowling.com retired pages | 115 | 118 | 36 |
| Hammer | 188 | hammerbowling.com `retired-balls` | 154 | 188 | 43 |
| Ebonite | 185 | ebonite.com `retired-balls` | 135 | 185 | 25 |
| Track | 164 | trackbowling.com `retired-balls` | 116 | 164 | 24 |

- **Brunswick family:** read from the manufacturer's own retired pages (spec table, per-weight core numbers). Older pages often give RG/diff only for 16 lb: those stay null with the 16 lb numbers in `notes`. Two printed values outside what a ball can be (Raw Hammer Burn RG 0.48, Track 300T diff 0.090) were dropped and noted. 13 Brunswick polyester designs returned a server error on every try and are not included (Flame, Leopard, Medusa, Pink Zebra, Purple Cheetah, Skull, Snake, Spider, Spiral Red/Black, Spiral Yellow/Blue/Black, Sun and Moon, Sunflower, Team Brunswick).
- **Storm, Roto Grip, 900 Global, Motiv:** Storm Products deletes a ball's page when it's retired and Motiv blocks bulk downloads, so specs come from **bowwwl.com** (fan-run database), as Shayne chose. Every record says so in `notes` and has no photo (bowwwl hosts its own copies). Only balls bowwwl flags *Discontinued* are added; unflagged ones missing from the current lineup were current balls under another name (bowwwl "Hustle M-M" = "Hustle M+M") or overseas releases that may still be sold. bowwwl "MB Diff" is stored as `int_diff_15`. 115 of Motiv's own 125 Retired Balls names matched a bowwwl record (the rest are colorway naming differences); those records say so.
- **Not collected:** retailer ratings, motion chart and a reaction description. The expected reaction of almost every retired ball is therefore a **spec estimate (low confidence, labelled)**; 10 Rhino colorways share the current Rhino's motion chart.
- **Verification:** an independent re-check of 40 random retired balls (4 per brand) against their source pages found 15 lb RG/diff/int diff correct on 118 of 120 values (2 misses, now fixed) and every ball marked retired. Parser fixes from that check: labels inside values ("Low RG Asymmetric", "Factory Finish Polish"), a "Weights" table header, lowercase labels. Remaining judgment calls: `cover_type` is `other` (and listed in `missing`) when no cover type is printed, and is taken from the coverstock name when that name says Pearl/Solid/Hybrid/Urethane/Polyester; core type is taken from the core name when it says Symmetric/Asymmetric; a mass bias printed without a weight stays in `notes`.
- All 974 retired-ball photo links returned an image on 2026-10-27.

## Verification (2026-10-21)
- Independent re-check of 24 randomly sampled balls against manufacturer pages and tech sheets: **15 lb RG, differential and intermediate differential matched on 24/24.** Three other fields were wrong and are fixed (Vengeance Returns oil, Mix Platinum oil, Danger Zone core type); one ball turned out retired (Supra Clutch, removed).
- Lesson: `recommended_oil` and `core_type` are the weakest fields — several came from bowling.com or bowwwl.com when the manufacturer doesn't state them. Records say so in `notes`.
- Migration + seed applied to Postgres 16 twice (idempotent); constraints reject out-of-range values.

## Known gaps and judgment calls
- Scales differ by source; the linear mapping onto 1–10 is a starting point. A ball's measured breakpoint/entry on known patterns should eventually outrank its catalog rating.
- 37 balls have no RG/diff published (mostly spare/Viz-A-Ball lines; Hammer Axe; Motiv Designer Series).
- Some core types come from bowwwl.com (Hammer) or were inferred as symmetric when no ASY value is published (Ebonite/Track); each record's `notes` says so.
- Motiv: Covert VIP EXJ may not be current (limited edition, not in Motiv's Ball Guide). Supra Clutch was removed — Motiv has retired it. Frenzy and Aspire specs conflict with bowling.com; Motiv's values used.
- Storm Monsoon: Storm's published intermediate diff (0.2) is impossible for a symmetric core; left null.
- Several balls list release dates after 2026-10-21 but are already in the manufacturers' current lineups.
- Hammer, Raw Hammer, Axe, Storm Mix/Ice Storm/Tropical Surge and Brunswick TZone/Viz-A-Ball colorways are separate records because they're sold as separate products.

## Drilling and surface: the bowler's own ball
The catalog reaction is the ball **out of the box**. A bowler's ball usually differs, and LaneSight applies what they record in their profile:

- **Layout** (`ball_configurations`, versioned) — Dual Angle `drill angle × pin-to-PAP × VAL angle` (e.g. `50 x 4.5 x 40`), VLS `pin-to-PAP × PSA-to-PAP × pin buffer` (e.g. `4 x 4 x 2`), the individual columns, or just **pin up / pin down** (`pin_position`) when that's all they know.
- **Current surface** (`surface_events`, append-only) — grit and whether it was polished. Bowlers can re-sand or polish at any time; each change is a new event, and each shot stores the `surface_event_id` it was thrown with so history isn't rewritten.

`configured_reaction(catalog_row, configuration, latest_surface_event)` (`lanesight_core/arsenal/configured.py`) starts from the box reaction and adds one explained adjustment per recorded variable. `user_ball_current` (migration 003) returns each ball's latest configuration and surface.

| Variable | Direction applied | Source |
|---|---|---|
| Pin-to-PAP | Flare (total hook) peaks around 3¾"; shorter = smooth, early; longer (4.5–6") = more length, stronger downlane | Storm VLS guide; MDM Coaching |
| Drill angle | Larger = later roll (more length); smaller = earlier | MDM Coaching (Dual Angle) |
| VAL angle | Small (pin up, 30–45°) = faster, snappier transition; large (pin down, 65–90°) = smoother | MDM Coaching (Dual Angle) |
| PSA-to-PAP (asymmetric only) | Short = earlier, smoother direction change; long = later, sharper; past 4" weaker | Storm VLS / pin-buffer guides |
| Pin buffer | Short = quicker skid-hook-roll; long = slower, smoother | Storm VLS guide |
| Pin up / down (when no angles given) | Up = more flare, stronger backend; down = smoother. Length unchanged | Storm, "Pin Up vs. Pin Down" |
| Surface vs box finish | Lower grit = earlier, smoother, more hook in oil; higher grit / polish = more length, sharper backend | bowling.com surface guide |

**How sure it is.** The sources give directions, not magnitudes, so the sizes are provisional (status `best_effort`, version `ls-configured-0.1-provisional`):
- Adjustments are measured from a reference layout (Dual Angle 45 × 4 × 45; VLS 4 × 4 × 2). A ball drilled at the reference keeps its catalog reaction.
- Each layout effect is scaled by the ball's differential (and intermediate differential for PSA). Low-diff and polyester balls barely change.
- Layout and surface are each capped at ±2.5 points per axis.
- Every adjusted axis is labeled `catalog+layout`, `catalog+surface` or both, with a plain-language reason per adjustment.

**Next step:** once a bowler has measured shots with a given layout and surface (breakpoint and entry angle on known patterns), those measurements should override these estimates. That isn't built yet. Oil absorption and games since the last resurface aren't modeled yet either.

## Weekly refresh
A scheduled task runs `REFRESH.md` every week (it also carries the retired balls over; the first sync after the backfill upserts ~2,077 rows in ~150 chunks):
1. It loads anything merged to `main` into Supabase, upserting only rows whose `source_hash` changed.
2. It checks every brand's current lineup and adds new balls in full, following `RECORD_SPEC.md`.
3. Balls no longer listed are **retired, never deleted** (`status = 'discontinued'`, `discontinued_on`), because arsenals point at them.
4. It picks up a new Brunswick motion chart when one is issued.
5. It opens a pull request for review. Nothing reaches `main` or Supabase without a merge.

A collection that would retire over 30% of a brand at once is refused as a likely broken scrape. Tools: `lanesight_core/arsenal/refresh.py` (`merge`, `summarize`, `check-images`, `digest`, `sync-sql`); migration `005_ball_catalog_refresh.sql`.

## Recommendations
`lanesight_core/arsenal/recommend.py` (status `best_effort`, provisional until coach / pro-shop review, BUILD_PLAN M4-08):
- `rank_for_condition(balls, Condition(...))` — target hook/length from oil volume or level, pattern length, rev rate and speed; ranks balls and explains misfits ("stronger than needed", "built for heavy oil").
- `arsenal_gaps(owned, catalog)` — catalog balls farthest from the bowler's arsenal in hook × length × backend space.
- For the bowler's own balls, pass `as_rankable(row, configured_reaction(...))` so ranking uses their drilled, current-surface reaction.
