# Weekly ball catalog refresh — runbook

Run every week by a scheduled task (and by hand whenever needed). Goal: keep `ball_models` current with each brand's lineup, **with Shayne reviewing every change as a pull request** before it reaches Supabase.

Each run does two things:
- **A. Sync merged changes to Supabase:** loads whatever is on `main` that Supabase doesn't have yet (last week's merged PR).
- **B. Refresh the lineup:** collects this week's changes and opens a new PR.

Never push to `main`. Never delete a ball. Never guess a value.

| | |
|---|---|
| Repo | `lafoonch-blip/LaneSight` (code in `lanesight-core/`) |
| Supabase | project **LaneSight**, ref `europwryibstnmipbvam` (VendHub org) |
| Brands | Storm, Roto Grip, 900 Global, Brunswick, DV8, Radical, Hammer, Ebonite, Track, Motiv (Columbia 300 retired in 2026) |
| Record format | `RECORD_SPEC.md` |
| Tools | `python -m lanesight_core.arsenal.refresh {merge,summarize,check-images,sync-sql}` and `python -m lanesight_core.arsenal.build_seed` |

## 0. Setup
```
git clone https://github.com/lafoonch-blip/LaneSight && cd LaneSight/lanesight-core
pip install -e '.[dev]'          # numpy/opencv come with it; the catalog code itself is stdlib-only
python -m pytest -q tests/test_arsenal.py tests/test_configured.py tests/test_refresh.py
```
Stop and report if those tests fail on `main`.

## A. Sync `main` → Supabase (always first)
0. **Quick check first.** Run `python -m lanesight_core.arsenal.refresh digest data/ball_catalog/catalog.json`, then run its `db_query` with `execute_sql`. If `n` and `digest` match, Supabase is already in sync: skip to B.
1. Read what Supabase has (Supabase connector, `execute_sql` on `europwryibstnmipbvam`):
   `select manufacturer || '|' || name as key, source_hash from ball_models;` → save the rows as `db_hashes.json` (a list of `{key, source_hash}`).
2. `python -m lanesight_core.arsenal.refresh sync-sql data/ball_catalog/catalog.json db_hashes.json --out-dir /tmp/sync`
3. Run each `/tmp/sync/sync_NN.sql` with `execute_sql`, in order. They are upserts only.
4. Verify: re-run the step-0 digest check. Both values must match. If not, report the mismatch and stop. Do not retry blindly.
5. If the connector cancels a statement or cannot reach the project, report it and skip to B. Never apply catalog data any other way.

## B. Refresh the lineup
Work on a branch: `git checkout -b catalog-refresh/<YYYY-MM-DD>`. Save a copy of the current catalog: `cp data/ball_catalog/catalog.json /tmp/catalog_before.json`.

For **each brand** (one raw file each in `data/ball_catalog/raw/`):
1. **Get the current lineup** from the manufacturer's own listing (sources below). Record the exact listing URL.
2. **Compare names** with the brand's raw file (`status: current` records):
   - *Still listed:* carry the existing record over unchanged.
   - *New:* collect a full record per `RECORD_SPEC.md`: 15 lb specs, image URL, ratings, motion chart and source URLs. Unpublished values are null and listed in `missing`.
   - *No longer listed:* leave it out of the fresh file; merge retires it.
   - *Release date in the past week:* re-fetch its manufacturer page. Specs are sometimes corrected right after launch.
3. Write `fresh/<brand>.json` (current lineup only), then run `python -m lanesight_core.arsenal.refresh merge data/ball_catalog/raw/<brand>.json fresh/<brand>.json --today <YYYY-MM-DD>`.
   - Exit code 2 = **refused**: the fresh lineup is empty, fails validation, or would retire more than 30% of the brand.
   - On a refusal, re-check the listing. Use `--force` only if the site clearly shows the brand dropped that many balls, and say so in the PR.
   - If a brand's site is unreachable, skip that brand and note it in the PR. Never retire balls because a page failed to load.

**Brunswick motion chart.** Brunswick reissues the Ball Motion Comparison Chart about every two months. The current one is linked from Brunswick-family product pages; check whether its filename changed. If a new chart is out, update `motion_chart` (oil 1–16, shape 1–18, read off the poster) for every Brunswick, DV8, Radical, Hammer, Ebonite and Track ball on it, and set `source_url`. Balls not on the chart keep `motion_chart: null`.

Then:
4. **Build:** `python -m lanesight_core.arsenal.build_seed data/ball_catalog/raw --out data/ball_catalog/catalog.json --sql lanesight_core/models/seed_ball_catalog.sql --retrieved-at <YYYY-MM-DD>`. Any `REJECTED` line means fix the record in `raw/` (never patch the outputs) or drop the new ball and list it in the PR.
5. **Test:** `python -m pytest -q tests/test_arsenal.py tests/test_configured.py tests/test_refresh.py`. Everything must pass.
6. **Summarize:** `python -m lanesight_core.arsenal.refresh summarize /tmp/catalog_before.json data/ball_catalog/catalog.json --markdown`. Exit code 1 means a ball was removed from `raw/` instead of retired: fix that.
7. **Check photos:** `python -m lanesight_core.arsenal.refresh check-images data/ball_catalog/catalog.json`. List every broken link in the PR. Fix it only if the manufacturer moved the image (new URL found on its own page).
8. **Independent check of new balls:** re-fetch every new ball's source page and confirm RG, differential and intermediate differential (15 lb), coverstock and core type. List any mismatch in the PR and fix it from the source.
9. **No changes?** If the summary is `0 new · 0 changed · 0 retired · 0 back in lineup` and no image fixes were needed, open no PR. Report "no changes" and the per-brand lineup counts.
10. **Otherwise open a PR** into `main` titled `Ball catalog refresh <YYYY-MM-DD>: N new, N changed, N retired`. The body contains:
    - the step-6 summary;
    - lineup URLs checked per brand, and any brand skipped or refused, with the reason;
    - motion chart: unchanged, or the new filename;
    - image check results and the step-8 spot-check results;
    - the line "Merging this loads it into Supabase on the next weekly run."

    Commit only `lanesight-core/data/ball_catalog/**` and `lanesight-core/lanesight_core/models/seed_ball_catalog.sql`. End the commit message with the attribution lines your environment requires.

## Lineup sources (start here; follow redirects)
- **Storm, Roto Grip, 900 Global:** stormbowling.com (rotogrip.com and 900global.com redirect there). The site's product search API (`/api/v/1/products/search`, anonymous token from `/api/oauth2/token`) returns 15 lb specs, slider ratings and the product line. Storm product pages default to 16 lb specs, so take 15 lb values from the weight data or the tech sheet. Storm's "PSA" is stored as `int_diff_15`.
- **Brunswick, DV8, Radical, Hammer, Ebonite, Track:** Shopify stores, each with a `/collections/balls` listing and a retired-balls collection. Brunswick-family pages publish ASY (stored as `int_diff_15`) and a reaction label. Hammer's spare/Viz-A-Ball pages sometimes omit core data.
- **Motiv:** the Ball Guide (motivbowling.com/ball-guide/ball-guide.html) is the lineup; check against Motiv's Retired Balls listing. Product images come from bowling.com (`image_source: retailer`).
- **Retailer ratings:** the bowling.com product page for each new ball (hook/length labels; numbers only when shown with a scale).

## Never
- Push to `main`, force-push, or edit anything outside `data/ball_catalog/` and the generated seed SQL.
- Delete a ball, hand-edit `catalog.json` or `seed_ball_catalog.sql`, or invent a value. A missing value is `null` and goes in `missing`.
- Apply data to Supabase from an unmerged branch.
