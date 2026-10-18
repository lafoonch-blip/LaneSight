# LaneSight Achievements — Product Rules & Inventory
Status: PROPOSED RULE CATALOG (feature behavior governed by DEC-039; thresholds not validated)
Version: 1.0
Last Updated: 2026-10-18
Owner: Shayne
Governing: DEC-039; score separation DEC-038; Practice-only MVP DEC-035

## Product invariants
- Achievements **never add to or affect** LaneSight Score, its four components, or Score tier.
- Profile → Achievements: top earned showcase (max 3), pinned pursuits (max 3), In Progress, collections by category, complete/unlocked history, achievement detail with qualifying data, earned date, proof/source, progress.
- Recent Activity records each **first verified unlock per achievement level** exactly once; one celebratory in-app popup when first achieved (deferred until confirmed). Optionally larger animation for 300/800. No popup on mere reprocessing or repeated attainment.
- Locked and pending requirements distinguish *not earned* vs *insufficient/unavailable data*. Achievement progress formats are rule-specific (best single game, best 3-game series, running streak, cumulative total, baseline improvement).
- On source corrections reconcile/revoke as an explicit event with audit trail; don't silently retain fraudulent/invalid verified awards. Import older scores only with source and approval. Visibility/sharing opt-in.
- Rule status here is **SPEC-ONLY** unless subsequently marked implemented with code path and validation evidence; catalog thresholds are provisional examples to verify with bowlers.

## Inventory (provisional thresholds)
**Notation:** All scoring rules require finalized scores; series = contiguous verified 3-game series from one eligible event; intent metrics require target recorded *before* the shot; comparisons require same ball configuration and intended-line segment. Streaks require consecutive eligible opportunities, not merely consecutive uploaded videos. Do not award when intervening attempts are unknown.

| ID | Category | Achievement | Qualifying trigger | Progress type | Delivery |
|---|---|---|---|---|---|
| ACH-001 | Scoring | Century Club | game ≥100 | best game | MVP* |
| ACH-002 | Scoring | Breaking Through | game ≥150 | best game | MVP* |
| ACH-003 | Scoring | 200 Club | game ≥200 | best game | MVP* |
| ACH-004 | Scoring | High Roller | game ≥250 | best game | MVP* |
| ACH-005 | Scoring | Perfect Game | game =300 | best game | MVP* |
| ACH-006 | Scoring | 500 Series Club | 3-game series ≥500 | best series | MVP* |
| ACH-007 | Scoring | 600 Series Club | 3-game series ≥600 | best series | MVP* |
| ACH-008 | Scoring | 700 Series Club | 3-game series ≥700 | best series | MVP* |
| ACH-009 | Scoring | 800 Series Club | 3-game series ≥800 | best series | MVP* |
| ACH-010 | Accuracy | Dialed In | 10 eligible shots within ±1 arrow board | count qualifying | MVP+ |
| ACH-011 | Accuracy | Precision Master | ≥90% within ±1 arrow board, ≥30 intent-valid shots | window ratio | MVP+ |
| ACH-012 | Accuracy | Dead Center | one arrow error ≤0.25 board, only if measurement precision supports it | best error | Research |
| ACH-013 | Accuracy | Pocket Hunter | pocket on ≥80% of ≥30 classified first balls | window ratio | MVP+ |
| ACH-014 | Accuracy | Breakpoint Boss | ≥90% within ±2 boards of intended breakpoint, ≥30 shots | window ratio | MVP+ |
| ACH-015 | Accuracy | Sniper | 10 consecutive converted single-pin spare attempts | live/best streak | MVP+ |
| ACH-016 | Delivery | Speed Demon | measured speed >20 mph | best measured | MVP+ |
| ACH-017 | Delivery | Rev Machine | measured rev >450 rpm, uncertainty band supports threshold | best measured | MVP+ |
| ACH-018 | Delivery | Powerhouse | 10 valid shots ≥18 mph and ≥400 rpm each | count qualifying | MVP+ |
| ACH-019 | Delivery | Controlled Power | 10 strikes with validated personal speed/rev repeatability threshold (TBD) | window | Research |
| ACH-020 | Delivery | Efficiency Expert | ≥80% pocket hits in ≥30 classified shots | window ratio | MVP+ |
| ACH-021 | Consistency | Mr. Consistent | speed SD <0.5 mph across ≥30 comparable shots | window spread | MVP+ |
| ACH-022 | Consistency | Repeatable Release | rev coefficient of variation <5% across ≥30 comparable precise shots | window spread | MVP+ |
| ACH-023 | Consistency | Line Locked | 10 consecutive intent-valid shots within ±1 arrow board | live/best streak | MVP+ |
| ACH-024 | Consistency | Steady Hand | 3 consecutive games all within 10 pins of each other | game window | MVP* |
| ACH-025 | Consistency | The Machine | 50 comparable shots meeting validated delivery variance target (TBD) | window | Research |
| ACH-026 | Improvement | Rising Star | LaneSight Score improves ≥25 from established baseline | baseline delta | After score |
| ACH-027 | Improvement | Level Up | score improves ≥50 | baseline delta | After score |
| ACH-028 | Improvement | Century Climber | score improves ≥100 | baseline delta | After score |
| ACH-029 | Improvement | Average Builder | qualified rolling game average rises ≥10 pins vs qualified baseline | baseline delta | MVP+ |
| ACH-030 | Improvement | Spare Specialist | qualified spare conversion rises ≥10 percentage points | baseline delta | MVP+ |
| ACH-031 | Improvement | Strike Evolution | qualified strike rate rises ≥10 percentage points | baseline delta | MVP+ |
| ACH-032 | Improvement | Personal Best | new verified personal best game after established baseline | new record | MVP* |
| ACH-033 | Improvement | New Heights | new **defined/implemented** session score high | new record | After score |
| ACH-034 | Competition | League Regular | 10 verified league nights | count | Post-MVP |
| ACH-035 | Competition | League Veteran | 100 verified league nights | count | Post-MVP |
| ACH-036 | Competition | League Champion | verified league title | event | Post-MVP |
| ACH-037 | Competition | Tournament Debut | first verified tournament result | count | Post-MVP |
| ACH-038 | Competition | Tournament Finalist | verified tournament final | event | Post-MVP |
| ACH-039 | Competition | Tournament Champion | verified tournament win | event | Post-MVP |
| ACH-040 | Competition | Podium Finisher | verified tournament top-three finish | event | Post-MVP |
| ACH-041 | Competition | Giant Slayer | verified win over a higher-ranked opponent; rank definition TBD | event | Research |
| ACH-042 | Streak | Turkey | 3 consecutive strikes | live/best streak | MVP* |
| ACH-043 | Streak | Four Bagger | 4 consecutive strikes | live/best streak | MVP* |
| ACH-044 | Streak | Six Pack | 6 consecutive strikes | live/best streak | MVP* |
| ACH-045 | Streak | Front Nine | strikes in frames 1–9 of a game | game sequence | MVP* |
| ACH-046 | Streak | Clean Game | no open frames in completed game | game result | MVP* |
| ACH-047 | Streak | Spare Streak | 10 consecutive converted spare opportunities | live/best streak | MVP* |
| ACH-048 | Streak | Practice Warrior | qualified practice sessions in four consecutive weeks | weeks | MVP+ |
| ACH-049 | Streak | Dedicated Bowler | 25 completed practice sessions | cumulative | MVP |
| ACH-050 | Platform | Welcome to LaneSight | complete minimum bowler profile | one-time event | MVP |
| ACH-051 | Platform | First Analysis | first valid analyzed shot | one-time event | MVP |
| ACH-052 | Platform | Getting Started | first completed analyzed session | one-time event | MVP |
| ACH-053 | Platform | Data Driven | 100 valid analyzed shots | cumulative | MVP |
| ACH-054 | Platform | Shot Scientist | 1,000 valid analyzed shots | cumulative | MVP |
| ACH-055 | Platform | Arsenal Builder | 5 distinct user balls recorded | cumulative | MVP |
| ACH-056 | Platform | Silver Status | first qualified LaneSight Silver tier | first-tier event | After score |
| ACH-057 | Platform | Gold Status | first qualified Gold | first-tier event | After score |
| ACH-058 | Platform | Platinum Status | first qualified Platinum | first-tier event | After score |
| ACH-059 | Platform | Onyx Club | first qualified Onyx | first-tier event | After score |
| ACH-060 | Platform | Hall of Fame | 100 distinct verified achievement unlocks/levels; impossible until enough exist | cumulative | Future |

*MVP* = only if verified complete-game/frame/series capture or user-confirmed scoring is available in Practice MVP. No assumed sanctioned/league data.

## Example progression UI
- 700 Series Club: personal-best qualifying series 684/700, not cumulative.
- Shot Scientist: 742/1000 valid shots, cumulative.
- Onyx Club: qualified current L=782; 68 points to threshold (when L is available).
- Strike streak: best 7, live 2; record the qualifying consecutive sequence.
- Unknown input: “Not trackable yet — complete a verified game” rather than false 0%.

## Suggested data contract (not yet implemented)
- `achievement_definitions`: stable ID, category, name, rule_type, rule_version, comparison, threshold, unit, window, sample_floor, evidence_required, minimum_quality, active, popup_priority, rollout_phase.
- `user_achievement_progress`: user_id, achievement_id, level, qualifying_count, current_value, best_value, last_qualifying_at, status, unavailable_reason, evidence_ref.
- `user_achievement_unlocks`: unique(user_id, achievement_id, level), unlocked_at, source_event_id, evidence_ref, rule_version, verification_state, revoked_at.
- `achievement_events`: idempotency_key, event_type, source_ref, user_id, occurred_at, received_at, source_authority, revision; emit separately idempotent `activity_item` and `notification` (delivered/read state).
- Recompute affected progress and unlock eligibility when scoring correction or user ball configuration changes; preserve an audit history.

## Acceptance criteria
1. A verified threshold crossing updates progress, writes exactly one unlock per level, emits one Recent Activity item and one first-unlock pop-up; replays do not duplicate.
2. Profile shows unlocked/locked/eligible/untrackable correctly, lets users pin up to three earned and three pursuing achievements.
3. No unlock writes to LaneSight Score or score components; no incomplete, low-confidence or duplicated evidence produces an unlock.
4. Corrected games reconcile awards transparently; historical import retains provenance.
5. League/tournament awards hidden in Practice-only MVP (DEC-035).
