# Feature Requirements Review: MVP vs MVP+
Status: DRAFT (for Shayne's review)  
Version: 1.0  
Last Updated: 2026-10-14  
Owner: Shayne  
Reviews: Google Doc "Feature Details" (2026-10-14) and the untitled "Phone Only / Sensor / Center" metric list  
Against: DEC-017–023, BUILD_PLAN v2.1, METRIC_CAPABILITIES v1.0

**Legend**
- **MVP:** fits DEC-019 and is feasible with what exists or is planned.
- **MVP+:** worth doing, but needs scale, partners, or data we won't have at launch.
- **Partner:** blocked on an outside party (USBC, centers, sensor vendors); not something to promise.
- **Decision:** conflicts with a current decision; needs a call.
- **Effort:** S = days · M = 1–3 weeks · L = 1–2 months

---

## 1. Headline findings
1. **Most of the list already matches the plan.** Profile, arsenal, sessions, shot detail, replay, adjustments, ball and oil-pattern stats are all DEC-019 MVP scope.
2. **"Bowling Center Enabled" stats don't need a center.** Video pin reading (14 of 14 correct so far) plus quick manual correction already produces strike %, spare conversion, leaves, total/average/high score and 9-or-better %. Per DEC-020 these are **MVP for every session**, not "league only" and not center-dependent. A center feed later just makes them official.
3. **The "Phone Only" list includes bowler metrics we scoped out.** Release feedback, drift and ball-to-ankle require tracking the bowler. The 2026-10-13 scope decision says ball and lane only, because glasses video never sees the bowler. → **Decision needed** (see §4).
4. **All sensor metrics depend on data access nobody has confirmed.** Ruby, F5 and Witsee have no documented API or export (R-02). Approach timing, swing height, hand position, axis and PAP from a sensor may start as manual or screenshot entry.
5. **League/tournament sessions in MVP have a capture problem.** Continuous capture with "this is me" recognition is post-MVP (League Mode). On league night a tripod sees every bowler on the pair, so the MVP needs per-shot record or tap-to-keep flow. Sanctioned-play rules on devices are still an open question.
6. **Missing from the list but core to the plan:**
   - shot intent ("where were you aiming?" / "did you hit your mark?"), which the execution-vs-lane coaching depends on (DEC-005/006)
   - capture setup guidance and tier badges (DEC-023)
   - manual score/pin correction
   - sensor variance display (DEC-021)

---

## 2. Feature-by-feature

### 2.1 Account and profile creation
| Feature | Tier | Effort | Notes |
|---|---|---|---|
| Email/password signup, remember me | MVP | S | Supabase Auth |
| Sign in with Google | MVP | S | |
| Sign in with Apple | MVP | S | **Required** by App Store rules if Google sign-in is offered |
| Face ID unlock | MVP | S | Biometric unlock of the stored session (Keychain), not face-based login |
| DoB at signup | MVP | S | **Legal flag:** youth bowling is large. Under-13 users trigger COPPA (parental consent) and minors need care around video. Decide: age-gate 13+ at launch, or build a parent/guardian flow (MVP+) |
| Gender (optional) | MVP | S | Useful later for comparisons; keep optional |
| Location (country/state/city) | MVP | S | |
| Home center lookup | MVP | M | No official center API. Seed a curated center list; add "suggest a center" for gaps. Verify the data source's terms |
| Profile photo | MVP | S | |

### 2.2 Bowler preferences and layout
| Feature | Tier | Effort | Notes |
|---|---|---|---|
| Left/right handed | MVP | S | Already in profile schema (M5-01) |
| One- vs two-handed | MVP | S | **Affects other features:** two-handers have no thumb hole, so "PAP up from thumb" and thumb-based presets don't apply. Spare targeting and typical rev ranges also differ |
| Middle finger pitch and span | MVP | S | Optional. Low analytic value today; useful for pro-shop/coaching later |
| Default layout presets (High/Med/Low × Angular/Strong/Smooth) | MVP | M | Non-standard naming, but user-friendly. Each preset needs a defined pin-to-PAP / drill angle / VAL mapping, reviewed by a pro-shop operator or coach (ties to M4-08) |
| Custom layout | MVP | S | Support **both** common systems: Dual Angle (drill angle, pin-to-PAP, VAL angle) and VLS (pin-to-PAP, pin buffer, PSA). "Core angle" isn't a standard term — likely means drill angle |
| PAP over/up | MVP | S | **Convention check:** PAP is normally measured from the grip center (over) and the midline (up), not "from the thumb." Match pro-shop convention or the numbers won't line up with what bowlers get from drillers |

### 2.3 USBC link
| Feature | Tier | Notes |
|---|---|---|
| Store USBC member ID | MVP (S) | Self-entered, labeled unverified |
| Member status / verification | Partner | No public API. DEC-019 already places USBC connection post-MVP |
| Membership renewal | Partner / MVP+ | Requires a USBC partnership |

### 2.4 Arsenal
| Feature | Tier | Effort | Notes |
|---|---|---|---|
| Add/edit ball | MVP | S | Schema exists (M5-02) |
| Brand/name from live catalog with RG, diff, cover, box finish | MVP | M–L | **There's no public live ball database to pull from.** MVP: a curated catalog of current/recent releases from major brands, from manufacturer spec pages (check terms), plus "add custom ball" for anything missing. Live feeds from manufacturers are MVP+/Partner |
| Weight | MVP | S | Needed for Power |
| Surface grit (box default, editable) | MVP | S | Stored as SurfaceEvents so history isn't overwritten (DEC-007) |
| Pitch/span per ball (defaults from profile) | MVP | S | |
| Layout per ball (defaults from profile) | MVP | S | Versioned BallConfiguration |

### 2.5 Legal, account, settings
| Feature | Tier | Notes |
|---|---|---|
| Terms of Service, Privacy Policy, version | MVP | Privacy Policy must cover video retention and deletion |
| Delete account | MVP | **Required** by App Store rules for apps with account creation. Must delete video and data |
| Manage subscriptions | MVP if paid at launch | StoreKit; pricing is still an open question |
| Sign out | MVP | |
| Units: mph / km/h; feet / meters | MVP (S) | Store internally in canonical units (ft, boards, mph); convert only for display. "Meters per hour" is presumably km/h or m/s |
| Session/video storage settings | MVP | Ties to retention policy (open question in Master Context) |
| Replay/heatmap and shot feedback settings | MVP | |

### 2.6 Bowler analytics
| Feature | Tier | Notes |
|---|---|---|
| LaneSight Score + trend | MVP | Needs a defined composite (e.g. pocket %, strike %, spare conversion, consistency). Write it as a DEC, like Power |
| World rank | MVP+ | Needs a large user base and anti-gaming rules; an early rank among 200 users looks empty |
| Filters: all time / 90 / 60 / 30 days / week / ball / center | MVP | Aggregations exist (M3-05) |
| Rev rate, speed | MVP | Speed Guaranteed; rev rate Best effort until blind-validated |
| Power | MVP (Best effort) | Defined from impact energy at pocket speed (proposed DEC-024). Tooltip shows energy plus pocket hit context, never "more power = more strikes" |
| Approach timing (total, pushaway, backswing, downswing, release) | Sensor only | Ruby has it; F5 doesn't; Witsee partial. Video won't measure it under current scope |
| Release: axis tilt, rotation, PAP | Sensor now; video MVP+ | Video axis needs ≥120 fps and is unbuilt (M1-10/11) |
| Hand position angles | Sensor only | Ruby-specific; vendor data access unverified |
| Game stats: games, average, high, strike %, spare %, 9-or-better % | **MVP, all sessions** | From video pin reading + manual correction. Not league-only |
| Ball comparison (rev, speed, power, strike %, games, shots), grouped by surface | MVP | Strong differentiator; schema supports it |
| Oil pattern stats | MVP | Pattern library seed data still to do (M5-04). Verify licensing for any published pattern library |
| Compare to other bowlers | MVP+ | Needs population data. A lighter MVP version: compare against your own best sessions |

### 2.7 Sessions
| Feature | Tier | Notes |
|---|---|---|
| Practice / League / Tournament types | MVP | Type is a tag. League and tournament need the capture flow below |
| Session tiles (score, date, time, duration, shots, avg rev/speed/score, type) | MVP | |
| Start session (type, optional ball, oil pattern default "house shot", "unknown") | MVP | Add a framing/fps check here (capture tier) |
| Change ball and surface mid-session | MVP | "Current Ball" control (Master Context §8) |
| Filter by type | MVP | |
| Session score (consistency, red→green ring, breakdown tooltip) | MVP | A consistency score prototype exists |
| Balls used + averages per ball | MVP | |
| Shot list (rev, speed, power, arrows, breakpoint, ball) | MVP | |
| Shot detail with virtual recreation, heatmap, loft, tracer stats | MVP | M6-01/02 prototypes |
| Sensor details (release, swing, approach, hand) | MVP if data access exists | Otherwise screenshot/manual entry |
| Pin result | **MVP from video** | Not center-dependent |
| Lane analytics (breakdown, transition) | MVP | M4-05 prototype. Must show inferred, not measured oil |
| League session capture | **Decision** | MVP: bowler taps record per shot (or starts/stops), or keeps clips by tapping. Continuous capture + recognition stays post-MVP. Confirm sanctioned-league device rules |
| Tournament: select oil pattern | MVP | Many tournaments restrict devices; add a rules note |

### 2.8 Adjustments
| Requirement | Tier | Notes |
|---|---|---|
| After every shot, from metrics + pin result | MVP | M4-03 rules engine |
| Uses session, lane transition, oil pattern, ball | MVP | M4-05/07 |
| Primary + secondary option | MVP (S) | Easy extension: rank candidate moves (feet/target, ball, speed) and return the top two |
| Ball change from arsenal | MVP basic, MVP+ refined | Basic: stronger/weaker by cover, RG, diff and surface. Refined: learned from each ball's observed reaction |
| Shown on session screen and shot detail | MVP | |
| "AI-driven" | MVP as rules + evidence | Keep a transparent rules engine that stores reason/evidence/confidence (M4-06). An LLM can phrase the advice later; it shouldn't make the call. Must still be able to say "no adjustment yet" and must not move the target after an execution miss (DEC-005/006) |

### 2.9 MVP+ sections in the doc
| Section | Agree MVP+? | Notes |
|---|---|---|
| Leagues (standings, schedule, subs, team stats) | Yes | This is league *management* data (DEC-004/013). Needs league software partners or LaneSight Leagues |
| Coaching | Yes | Cheap MVP version: share a read-only session link with your coach |
| Bowling center integration | Yes / Partner | Makes scores official; not needed for stats (DEC-020) |
| Social: friends, feed, kudos | Yes | Shareable replay cards could be a cheap MVP growth hook |
| YouTube/TikTok for streamers | Yes | Start with export of replay video/overlay; live streaming overlay later |
| Pattern Analyzer (line + ball recs from pattern + arsenal) | Yes | Pattern context is already MVP (M4-07); full analyzer needs per-ball reaction data |
| Unique bowler ID across USBC/leagues/centers | Partner | Data model supports it (ExternalIdentity); depends on partnerships |

---

## 3. "Phone Only" metric list check
| Metric | Status | Notes |
|---|---|---|
| Pocket hits | MVP, Guaranteed at 60 fps | Entry board + pins |
| Rev rate | MVP, Best effort | Blind validation pending |
| Speed | MVP, Guaranteed | |
| Energy at impact | Replaced by **Power** | |
| Carry (strike chance %) | MVP: carry % (strikes on pocket hits). Predicted strike % is MVP+ | Prediction needs a large dataset |
| Loft distance | MVP at ≥60 fps | Unavailable at 30 fps |
| Lane transition insights | MVP | |
| Release metrics and feedback | **Decision** | Video doesn't see release mechanics under current scope; sensor or MVP+ |
| Drift | **Decision** | Needs bowler's feet tracked at setup and slide. Tripod only; glasses can't |
| Ball to ankle | **Decision** | Needs bowler pose tracking. Tripod only |

## 4. Decisions needed
1. **Tripod bowler metrics (drift, ball-to-ankle, release feedback, swing/approach from video).** Option A: keep ball/lane-only scope. Option B: allow bowler metrics as tripod-only "Best effort" extras via pose estimation (MVP+). This doesn't break the glasses design if they're labeled Unavailable for moving camera.
2. **League-night capture flow for MVP** (per-shot record vs tap-to-keep) and a check on device rules in sanctioned league and tournament play.
3. **Age policy:** 13+ gate at launch vs youth/parent accounts.
4. **Definitions to write as DECs:** LaneSight Score, Session Score, Power (DEC-024), layout preset mappings.
5. **Ball catalog source** and its terms of use.

## 5. Additional features to consider
| Feature | Tier | Why |
|---|---|---|
| Shot intent entry + "Did you hit your mark?" prompt | **MVP** | Required for execution vs lane coaching; missing from the list |
| Capture assistant (framing overlay, fps/resolution check, tier badge) | **MVP** | DEC-023; prevents bad clips and support tickets |
| Manual score/pin correction | **MVP** | Pin reading won't be perfect; stats have to be fixable |
| Sensor screenshot/OCR import | MVP bridge | Gets Ruby/F5/Witsee data in before any API exists |
| LaneSight vs sensor variance view | MVP | DEC-021 |
| Offline capture and analysis queue | MVP | Bowling centers often have poor signal (C-04) |
| Spare coach: per-leave targets + conversion by pin | MVP | Biggest scoring gain for most league bowlers |
| Surface/maintenance reminders (games since resurface or oil extraction) | MVP+ | Uses data you already collect |
| Shot compare (two shots, balls or sessions side by side) | MVP+ | |
| Goals, personal bests, achievements | MVP+ | Retention |
| Data export (CSV) | MVP+ | Trust with serious bowlers and coaches |
| Coach share link (read-only) | MVP+ | Cheap first step toward Coaching |
| Audio Coach | MVP+ | In Master Context and Build Plan U-03; missing from the list |
| Baseline session at onboarding (5–10 shots) | MVP+ | Sets personal baselines for speed, revs and Power |
| Team Lane Management | Post-MVP | Already planned; strong network loop |

## 6. Suggested MVP cut (summary)
**In:** auth (email/Google/Apple/Face ID unlock), profile and preferences, layout presets + custom, arsenal with curated catalog, units/settings/legal/delete account, sessions (all three types, with the MVP capture flow), shot detail and replay, game stats from video, ball and oil-pattern stats, LaneSight and Session Scores, Power, primary/secondary adjustments, shot intent, capture assistant, manual correction, offline queue, sensor import + variance.

**MVP+:** world rank, comparison to other bowlers, predicted strike %, video axis/PAP, tripod bowler metrics (if approved), leagues, coaching, center integration, social, streaming, pattern analyzer, USBC verification/renewal, youth accounts, Audio Coach.
