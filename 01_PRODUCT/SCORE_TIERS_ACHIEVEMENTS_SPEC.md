# LaneSight Score, Tiers & Achievements — Dev Launch System Spec
Status: DRAFT (for Shayne's review)
Version: 0.3
Last Updated: 2026-10-25
Owner: Shayne
Builds on: ACHIEVEMENTS.md v1.1 (catalog + data contract), DEC-038/039/041, DEV_BUILD_PLAN §8 (formula `L-dev-0`), BENCHMARKS_AND_RECOMMENDATIONS_SPEC (owner-only rules)
Proposed home: `01_PRODUCT/SCORE_TIERS_ACHIEVEMENTS_SPEC.md` + migration `006_score_achievements.sql`

## 1. Scope for this launch
- LaneSight Score (`L-dev-0`), tiers, badge, score history, personal best: **live**.
- Achievements: the full engine plus the **subset of the catalog that works without pinfall** (§4). Everything else is defined in the database but inactive, shown as "Coming later".
- Unchanged rules: achievements **never** change the score or tier (DEC-039). No fabricated progress. "Not trackable yet" is different from 0%.

## 2. How the score is tracked
**Inputs:** only Measured or Best-effort shots that passed the confidence gate. Shot and Form clips feed different things: Form stats never feed the score (DEC-041).

**Recompute:** after every analyzed shot (serial queue), at session end, and after any correction or reprocess. Each recompute writes a `score_snapshot`.

**Window:** qualifying shots from the last 90 days. Smoothing stays TBD (DEC-041); dev uses a plain 90-day window and records `formula_version` so history can be recomputed later.

**Eligibility before a score is shown ("Building your LaneSight Score"):**

| Part | Needs (owner-editable) |
|---|---|
| Performance S' | ≥20 shots with entry board + entry angle |
| Accuracy A | ≥20 shots with intent (feet, arrows, breakpoint) set before the shot |
| Consistency C | ≥10 comparable shots (same ball configuration + same intended line) |
| Power P' | ≥10 shots with entry speed |

- Each part shows its own progress ("Accuracy 12/20 shots with a target"). Until all four are met, no overall score or tier is shown and nothing is reweighted.
- **Personal best:** the highest score from a session-end snapshot, not a mid-session one, so a single lucky recompute can't set it.

## 3. Tiers and badging
| Tier | Range |
|---|---|
| Bronze | 0–399 |
| Silver | 400–549 |
| Gold | 550–699 |
| Platinum | 700–849 |
| Onyx | 850–1000 |

**Tier changes are evaluated at session end only**, never mid-session, so the badge doesn't flicker while you bowl.
- **Promotion:** session-end L ≥ the next tier's floor.
- **Demotion (hysteresis):** session-end L is more than 15 points below the current tier's floor on **2 consecutive** sessions. Both 15 and 2 are owner-editable.
- **First time** reaching a tier: a `tier_event` (promotion, first = true), the Status achievement for that tier (ACH-056…059), and a **full-screen celebration**.
- **Regaining** a tier you held before: a `tier_event` (promotion, first = false) and a small banner. No achievement, no full-screen celebration.
- **Demotion:** a `tier_event` (demotion) and a quiet Recent Activity line ("Back to Gold — 12 points from Platinum"). No popup.

**Badge display:** Home score card, Stats → Score, Profile/Achievements header, and share card (later). Badge art per tier is an asset with locked, current and earned states.

## 4. Achievement catalog for this launch (no pinfall)
**Active now:**

| ID | Name | Rule (as adapted) | Progress type |
|---|---|---|---|
| ACH-050 | Welcome to LaneSight | profile complete (handedness, style, 1 ball) | one-time |
| ACH-051 | First Analysis | first valid analyzed shot | one-time |
| ACH-052 | Getting Started | first completed analyzed session | one-time |
| ACH-053 | Data Driven | 100 valid analyzed shots | cumulative |
| ACH-054 | Shot Scientist | 1,000 valid analyzed shots | cumulative |
| ACH-055 | Arsenal Builder | 5 balls in arsenal | cumulative |
| ACH-049 | Dedicated Bowler | 25 completed practice sessions | cumulative |
| ACH-048 | Practice Warrior | ≥1 qualifying session in 4 consecutive weeks | weekly streak |
| ACH-010 | Dialed In | 10 intent shots within ±1 board at the arrows | count qualifying |
| ACH-011 | Precision Master | ≥90% within ±1 arrow board over ≥30 intent shots | window ratio |
| ACH-013 | Pocket Hunter | entry board in pocket on ≥80% of ≥30 shots (**adapted:** all classified shots, not "first balls") | window ratio |
| ACH-014 | Breakpoint Boss | ≥90% within ±2 boards of intended breakpoint, ≥30 shots | window ratio |
| ACH-023 | Line Locked | 10 consecutive intent shots within ±1 arrow board | live/best streak |
| ACH-016 | Speed Demon | measured speed >20 mph | best measured |
| ACH-017 | Rev Machine | rev >450 rpm with the band entirely above 450 | best measured |
| ACH-018 | Powerhouse | 10 shots ≥18 mph and ≥400 rpm | count qualifying |
| ACH-020 | Efficiency Expert | **Redefined** (was a duplicate of Pocket Hunter): entry angle 4–6° on ≥80% of ≥30 shots | window ratio |
| ACH-021 | Mr. Consistent | speed SD <0.5 mph across ≥30 comparable shots | window spread |
| ACH-022 | Repeatable Release | rev CV <5% across ≥30 comparable shots whose rev band ≤ ±20 (needs 120 fps) | window spread |
| ACH-026/027/028 | Rising Star / Level Up / Century Climber | L up ≥25 / 50 / 100 from first qualified score | baseline delta |
| ACH-056…059 | Silver / Gold / Platinum Status, Onyx Club | first qualified tier | first-tier event |

**Proposed new Form achievements** (P1 metrics; owner approves before activation):
- FORM-001 **Post It**: finish hold ≥1.5 s on 10 deliveries.
- FORM-002 **Metronome**: swing-time SD ≤0.05 s over 10 consecutive deliveries.

**Inactive, shown as "Coming later":**
- **Need game scores or pinfall:** ACH-001…009, 015, 024, 029…033, 042…047.
- **Competition:** ACH-034…041.
- **Research:** ACH-012, 019, 025.
- **Future:** ACH-060.

## 5. Progress engine
Lives in `lanesight_core/achievements/` and runs in the Mac service after the shot pipeline and the score recompute. Definitions are seeded from `rules/achievements.yaml` and editable in the owner Rules page. Users see each achievement's name and description, never rule internals.

**Events in:**
- `shot.analyzed`
- `shot.corrected`
- `session.completed`
- `profile.updated`
- `arsenal.updated`
- `score.recomputed`
- `tier.changed`

Each event carries an idempotency key.

**Rule types:**

| Type | How progress is computed |
|---|---|
| `one_time` | condition true once |
| `cumulative` | running count |
| `count_qualifying` | count of shots meeting a condition |
| `window_ratio` | share of qualifying shots in a rolling window, only after the sample floor |
| `window_spread` | SD/CV over a comparable window |
| `best_measured` | best value whose uncertainty band clears the threshold |
| `streak` | live + best consecutive; an unknown or failed shot **breaks** the streak only if it was a real attempt with intent, and is skipped if it was unanalyzable (logged) |
| `weekly_streak` | consecutive calendar weeks with a qualifying session |
| `baseline_delta` | change from the first qualified score |
| `first_tier` | first `tier_event` promotion to that tier |

**Per evaluation:**
1. Upsert `user_achievement_progress` (`current_value`, `best_value`, `qualifying_count`, `status`: locked / in_progress / not_trackable + reason / unlocked).
2. If the threshold is crossed, insert into `user_achievement_unlocks`. The unique key (user, achievement, level) makes replays harmless.
3. On insert, emit one `activity_item` and one `notification`.

**Corrections:** re-evaluate the affected achievements. If the evidence no longer qualifies, set `revoked_at` with a reason and write an activity line. No popup.

## 6. How unlocks and tier changes appear
- **When:** never during recording. A notification surfaces at the next quiet moment:
  - on the shot card, after results load
  - otherwise, at session end
- **Pacing:** at most one popup per shot.
  - Priority: first-tier celebration > achievement (by `popup_priority`).
  - Extra unlocks are batched into the session summary ("+2 more unlocked").
- **Achievement popup:** badge, name, one-line reason, the qualifying value (e.g. "10 / 10 within 1 board"), and View / Dismiss buttons. Optional spoken line: "Achievement unlocked: Line Locked."
- **Tier celebration:** full screen with the new badge, score, "You reached Platinum", distance to the next tier, and the Status achievement. Larger animation for Platinum and Onyx.
- **Shot card footer:** small progress nudges, e.g. "Score +3 · Line Locked 7/10".
- **Achievements screen:**
  - unlocked count (active catalog only)
  - showcase: 3 pinned earned
  - close to unlocking: 3 pinned or highest percentage
  - categories
  - "Coming later" group
  - detail: rule text, progress, qualifying shots (linked), earned date, rule version
- **Recent Activity on Home:** every unlock, tier change and revocation, once.

## 7. Database — migration `006_score_achievements.sql` (draft)
```sql
-- Score formula versions (owner-managed)
create table score_formula_version (
  id text primary key,                 -- 'L-dev-0', later 'DEC-038-v1'
  description text not null,
  params jsonb not null,               -- weights, pocket range, angle range, power ref ranges, eligibility floors, hysteresis
  status text not null check (status in ('draft','active','retired')),
  created_at timestamptz not null default now()
);

-- Every recompute
create table score_snapshot (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  formula_version text not null references score_formula_version(id),
  computed_at timestamptz not null default now(),
  trigger text not null check (trigger in ('shot','session_end','correction','backfill')),
  session_id uuid references session(id),
  eligible boolean not null,
  score int check (score between 0 and 1000),          -- null when not eligible
  s_perf numeric, a_acc numeric, c_cons numeric, p_power numeric,  -- 0-100 or null
  eligibility jsonb not null,          -- per-part counts vs floors
  inputs jsonb not null,               -- shot ids + window summary for audit/recompute
  tier text check (tier in ('bronze','silver','gold','platinum','onyx'))
);
create index on score_snapshot (user_id, computed_at desc);

-- Current tier state (one row per user)
create table user_tier_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  tier text,
  score int,
  best_score int,
  best_score_at timestamptz,
  first_qualified_score int,           -- baseline for ACH-026..028
  below_floor_sessions int not null default 0,
  updated_at timestamptz not null default now()
);

create table tier_event (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  from_tier text, to_tier text not null,
  kind text not null check (kind in ('promotion','demotion')),
  first_time boolean not null,
  score int not null,
  snapshot_id uuid not null references score_snapshot(id),
  occurred_at timestamptz not null default now()
);

-- Achievements
create table achievement_definition (
  id text primary key,                 -- 'ACH-023'
  category text not null,
  name text not null,
  description text not null,           -- user-facing
  rule_type text not null,
  params jsonb not null,               -- thresholds, windows, sample floors, quality gates
  levels int not null default 1,
  rule_version int not null default 1,
  popup_priority int not null default 50,
  status text not null check (status in ('active','coming_later','draft','retired')),
  inactive_reason text,                -- 'needs game scores', etc.
  badge_asset text
);

create table user_achievement_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  achievement_id text not null references achievement_definition(id),
  level int not null default 1,
  status text not null check (status in ('locked','in_progress','not_trackable','unlocked')),
  current_value numeric, best_value numeric, target_value numeric,
  qualifying_count int, sample_count int,
  unavailable_reason text,
  last_event_at timestamptz,
  evidence_ref jsonb,
  primary key (user_id, achievement_id, level)
);

create table user_achievement_unlock (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  achievement_id text not null references achievement_definition(id),
  level int not null default 1,
  unlocked_at timestamptz not null default now(),
  value numeric,
  source_event_id uuid,
  evidence_ref jsonb not null,
  rule_version int not null,
  revoked_at timestamptz, revoke_reason text,
  unique (user_id, achievement_id, level)
);

create table user_achievement_pin (
  user_id uuid not null references auth.users(id) on delete cascade,
  achievement_id text not null references achievement_definition(id),
  kind text not null check (kind in ('showcase','pursuit')),
  position int not null check (position between 1 and 3),
  primary key (user_id, kind, position)
);

create table engine_event (
  idempotency_key text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null,
  source_ref jsonb not null,
  occurred_at timestamptz not null,
  processed_at timestamptz
);

create table activity_item (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('achievement_unlocked','achievement_revoked','tier_promotion','tier_demotion','personal_best')),
  ref_id text not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  unique (user_id, kind, ref_id)
);

create table notification (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('achievement_popup','tier_celebration','tier_banner')),
  ref_id text not null,
  priority int not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  delivered_at timestamptz, dismissed_at timestamptz,
  unique (user_id, kind, ref_id)
);
```
**RLS:**
- Users read their own rows in `score_snapshot`, `user_tier_state`, `tier_event`, `user_achievement_*`, `activity_item` and `notification`.
- Users write only `user_achievement_pin` and `notification.dismissed_at`.
- `achievement_definition`: users read only `id`, `name`, `description`, `category`, `status`, `inactive_reason` and `badge_asset`, through a view. `params` stays admin-only.
- `score_formula_version.params`: admin-only.
- All other writes go through the service role on the Mac service.

## 8. API additions
| Endpoint | Returns |
|---|---|
| `GET /me/score` | current score, tier, parts, eligibility, best |
| `GET /me/score/history?range=` | daily session-end snapshots |
| `GET /me/achievements` | progress grouped by category, plus pins |
| `GET /me/achievements/{id}` | detail + evidence shots |
| `PUT /me/achievements/pins` | sets showcase / pursuit pins |
| `GET /me/notifications?undelivered=1` | pending popups and banners |
| `POST /me/notifications/{id}/delivered` and `/dismiss` | marks a notification shown or dismissed |
| `GET /me/activity` | Recent Activity items |

The shot result payload includes `score_delta` and `achievement_nudges[]` for the shot-card footer.

## 9. Shot card changes (same pass)
- **Target vs actual line:** a lane diagram draws the intended line (feet → arrows → breakpoint, entered on the capture screen) against the actual line (laydown → arrows → breakpoint → entry), with per-point miss in boards. The execution class appears as plain text ("On target — the lane hooked less", "Missed left at the arrows").
  - "Did you hit your mark?" is removed because the target is known.
  - With no target entered, Accuracy shows "Set a target on the capture screen".
- ~~**Form on shot clips**~~ **Superseded by DEC-056 (2026-10-25):** Shot Analysis results show shot metrics only; form metrics appear only in Form Analysis results, for now.
- **Sensor question after each shot:** "Was a sensor in the ball?" No / Yes (pick from the sensors in your profile). Stored on the shot as `sensor_used` + `sensor_id` so the readings can be matched later. Sensor brand names come only from the bowler's own profile entries; no brand names are built into the app screens.

## 10. Decisions (2026-10-22)
1. **Tier hysteresis:** approved: 15 points below the floor on 2 consecutive sessions.
2. **Eligibility floors:** approved: 20 / 20 / 10 / 10 shots.
3. **FORM-001 Post It and FORM-002 Metronome:** go live now, status active.
4. **Score-improvement achievements (026–028):** go live now on `L-dev-0`. All score history, tier state and achievement progress/unlocks can be **reset before Beta** (owner-only reset in the Rules page: archive then clear `score_snapshot`, `user_tier_state`, `tier_event`, `user_achievement_*`, `activity_item`, `notification` for selected users; definitions are kept).
