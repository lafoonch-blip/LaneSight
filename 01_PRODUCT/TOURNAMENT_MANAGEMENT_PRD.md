# LaneSight Tournament Management PRD
Status: PROPOSED — post-MVP expansion
Version: 1.0
Last Updated: 2026-10-15
Owner: Shayne
Source: Tournament management requirements and tournament-led acquisition strategy discussed 2026-10-15

## 1. Product objective
Tournament management is LaneSight's **first major post-MVP growth initiative**. Acquire tournament directors as distribution partners; their events bring bowlers into a persistent LaneSight profile, then activate shot analysis, arsenal, coaching and league features. Primary business outcome is acquired and retained bowlers, not director software revenue. This is a proposed sequencing change to the current bowler-first roadmap, subject to formal decision approval. The shot-analysis MVP scope and gates remain unchanged.

## 2. Target users and jobs
- Director: configure, register, check in, assign squads/lanes, enter/correct scores, run standings, brackets, pots and payouts; export records.
- Bowler: find tournament, create or claim profile, register, receive updates, see standings/results, retain history, explore LaneSight performance tools.
- Center staff: collaborate on event logistics with permissioned access.
- Spectator: see public event pages and standings without a login.

## 3. Acquisition funnel and onboarding policy
**Proposed policy:** Require a LaneSight profile for self-service tournament registration, but do not require a native app install to register. Use mobile web signup with Apple, Google or email, then prompt installation for standings, notifications and results. Directors can register walk-ins or people unable to create accounts; send a secure claim invitation after the event. Never block an event because a participant cannot install an app. Measure conversion before considering app-only registration.
1. Director creates/publishes event and shares link/QR.
2. Bowler sees event details, eligibility, fees and privacy notice.
3. Bowler signs in or creates lightweight profile; reuse existing identity and avoid duplicate accounts.
4. Bowler registers, chooses squad and receives confirmation.
5. Prompt app installation for event updates, live standings and results.
6. After event, attach verified results to profile and introduce shot analysis/arsenal/coaching.
7. Invite director to repeat event; referrals drive more bowlers and organizers.

## 4. Launch scope and feature priorities
P0 = required for first supervised commercial tournament launch; P1 = full TournamentBowl-replacement readiness; P2 = later.

| ID | Requirement | Priority |
|---|---|---|
| TM-001 | Create/edit/duplicate/cancel/publish event; center, date/time, lanes, capacity, rules, fees | P0 |
| TM-002 | Singles scratch and handicap formats; configurable handicap base/percent, rounding and tie-break | P0 |
| TM-003 | Multiple squads, capacities, registrations, lane assignments and check-in | P0 |
| TM-004 | Public mobile event page, search/discovery, shareable link and QR | P0 |
| TM-005 | Profile-based web registration, Apple/Google/email sign-in, confirmations | P0 |
| TM-006 | Director-assisted walk-in registration, guest identity claim and deduplication | P0 |
| TM-007 | Accepted average capture with source, effective date and verification status | P0 |
| TM-008 | Director roster, role permissions and staff access | P0 |
| TM-009 | Manual game score entry, validation, correction history and audit | P0 |
| TM-010 | Provisional/live/final standings by event/squad/division; tie-breaks | P0 |
| TM-011 | Scratch and handicap totals, prize fund configuration, reviewed payout report | P0 |
| TM-012 | Manual fee/payment status tracking, refund/withdrawal status | P0 |
| TM-013 | Public spectator standings, bowler tournament history, result provenance | P0 |
| TM-014 | CSV exports of registrations, scores, standings and payout obligations | P0 |
| TM-015 | Event/app acquisition analytics, funnel attribution and consent preferences | P0 |
| TM-016 | Operational incident, backup, recovery and support workflow | P0 |
| TM-017 | Scratch/handicap brackets, automatic pairing, advancement and settlements | P1 |
| TM-018 | Side pots (high game/series), entry fees and settlements | P1 |
| TM-019 | Doubles/team events, divisions, multi-round qualifying/finals | P1 |
| TM-020 | Waitlists, templates, series standings and recurring organizer tools | P1 |
| TM-021 | Online entry collection, refunds and financial reconciliation | P1 |
| TM-022 | Push/email reminders, tournament follow-up and personalized activation | P1 |
| TM-023 | Bowling-center scoring integrations via authorized ScoringAdapter | P2 / Partner |
| TM-024 | USBC verification and authorized sanctioned record integration | P2 / Partner |
| TM-025 | Automated prize disbursement, complex match play/stepladder | P2 |
| TM-026 | Tournament-specific performance comparisons and shot-level analytics links | P2 |

**Launch positioning:** P0 supports a narrow singles tournament pilot; do not advertise full TournamentBowl parity until brackets, side pots and other required local formats are proven.

## 5. Core data requirements
Reuse LaneSight User and BowlerProfile, plus ExternalIdentity/ScoreRecord where appropriate. Add:
- Organization(id, name, billing/operational status); OrganizationMember(user_id, organization_id, role)
- BowlingCenter(id, location, time_zone, lane_count)
- Tournament(id, organization_id, center_id, title, status, dates, rules_version, entry_fee_cents, visibility)
- TournamentDivision(id, tournament_id, eligibility, format, handicap_rules)
- Squad(id, tournament_id, start_at, lane_capacity, assigned_lanes)
- Registration(id, tournament_id, bowler_profile_id nullable, guest_claim_token_hash, squad_id, status, source_campaign)
- AverageRecord(bowler_id, average, source, effective_date, verified_by)
- EntryPayment(id, registration_id, amount_cents, payment_method, status, provider_reference nullable)
- GameScore(id, registration_id, round, game_index, scratch_pins, handicap_pins, revision, status)
- ScoreAudit(id, score_id, actor_id, before, after, reason, timestamp)
- StandingSnapshot(tournament_id, division_id, rank, total, tie_break, provisional, computed_at, rules_version)
- PrizeAllocation(tournament_id, recipient_id, amount_cents, approval_status, payment_status)
- Bracket, BracketEntry, BracketMatch and SidePotEntry (P1)
- AcquisitionAttribution(profile_id, first_event_id, director_id, channel, timestamps, consent_status)
- AppActivation(profile_id, app_install_at, first_shot_at, first_session_at, retention_cohorts)
All personal data is private by default; public leaderboards show only consented/necessary competition fields. Record provenance and authority; do not silently blend official tournament results with self-reported practice results. Use stable IDs, immutable audit history, integer cents, UTC timestamps plus center timezone, idempotent submissions, and transactional score/standing updates. Retain result history under documented policies.

## 6. Rules engine and reliability
Per-game handicap example: max(0, floor((base - accepted_average) * percentage)); rounding, caps, negative handicap, average qualification and tie-break policy must be event-configurable and versioned. Final standings and prize allocations must be reproducible from accepted inputs. Director approval required for finalization; correction after finalization must produce an auditable amended result. Live updates should distinguish incomplete squads from final placements.

## 7. Architecture
Web-first director console and mobile-friendly registration pages, with LaneSight iOS app as retention surface. Reuse Postgres/Supabase Auth and row-level tenant isolation, API services, job queues, realtime standings and shared identity. Keep scoring/settlement rules server-side and independently testable. Add adapters for external scoring only after authorized access is verified. Consider Stripe Connect for future payments, subject to legal, underwriting, processor terms and compliance review. Do not treat any third-party integration as guaranteed.

## 8. Commercial model (hypothesis)
Offer free/low-cost basic director tools to maximize event adoption. Test paid advanced organizer functionality and optional registration fees after validating willingness to pay. Measure fully loaded acquisition cost, processing costs, support cost and organizer retention. Never assume every registration is a unique bowler.

## 9. Launch gates
- At least 3 supervised local tournaments, including scratch, handicap and multi-squad scenarios.
- 100% scoring and payout accuracy on a documented edge-case test suite.
- Corrected scores trigger auditable recalculation; no lost confirmed submissions.
- Guest claim and duplicate-profile merging tested.
- Staff cannot access other organizers' private records.
- Mobile registration and director recovery paths work during live-event disruption.
- Public results distinguish provisional from final.
- Director confirms event can operate without spreadsheets for P0-supported formats.
- Support runbook, backup/restore rehearsal, privacy terms and accessibility review completed.

## 10. Acquisition KPIs
North star: **incremental 90-day retained bowlers acquired per active tournament director**.
Supporting metrics: active directors; events/director; registrations/event; unique new bowlers/event; profile creation rate; app install rate; first shot analysis within 30 days; 30/90-day retention; cost per retained bowler; director repeat usage; event completion; incident rate. Track web-registration dropoff separately from app-install conversion. Initial numeric targets require pilot baselines; avoid treating illustrative scenarios as forecasts.

## 11. Delivery sequence
0. Director discovery and tournament-rule inventory.
1. Tournament operations foundation: event setup, squads, registrations, director roles.
2. Manual scoring, provisional/final standings, payouts, exports.
3. Supervised Richmond-area pilot and funnel instrumentation.
4. Brackets, pots, more formats, online payments, recurring organizer capabilities.
5. Center/USBC integrations, expanded analytics and league management.

## 12. Decisions and dependencies
- **Proposed DEC-026:** After DEC-019 MVP exit, prioritize tournament management ahead of full league management as a tournament-led acquisition engine. This refines DEC-013's distribution sequence but retains the bowler profile as core. Await acceptance before changing canonical decisions or build plan.
- Validate mandatory account policy with directors and bowlers; native app download is encouraged, not mandatory for registration.
- Validate which bracket, pot and event formats are deal-breakers for local directors before setting GA scope.
- Determine age/minor registration policy, public results/privacy, data retention, payment handling, tournament rules and sanctioned-play constraints.
- No edits to DECISIONS.md or BUILD_PLAN.md are implied by this proposed PRD.
