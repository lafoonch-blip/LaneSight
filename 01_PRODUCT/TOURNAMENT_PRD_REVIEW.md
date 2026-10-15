# Tournament Management PRD — Review
Status: DRAFT (for Shayne's review; proposed DEC changes not yet applied)
Version: 1.0
Last Updated: 2026-10-15
Owner: Shayne
Reviews: `01_PRODUCT/TOURNAMENT_MANAGEMENT_PRD.md` v1.0
Against: Master Context v1.2, CURRENT_STATE v1.5, DECISIONS v1.4 (DEC-001–025), BUILD_PLAN v2.2, FEATURE_REVIEW v1.0

---

## 1. Bottom line
1. **The strategy is sound but it reverses an accepted principle, so it needs a real decision, not a "refinement."** DEC-013 and Master Context §2/§15/§16 say: earn bowler pull first, then managers adopt. DEC-026 says: win managers first, they deliver bowlers. That is a different go-to-market. Record it as superseding the relevant parts of DEC-013 and update the Master Context ladder.
2. **Accept DEC-026 conditionally.** Gate it on discovery (T-0 below): at least 3 Richmond-area directors agree to pilot. Discovery costs days and can start now; the build can't start until MVP auth/cloud exist anyway.
3. **Brackets and high-game pots belong in the first public launch, but as record-keeping only.** If a director still needs TournamentBowl or paper for brackets on the same event, they won't switch. LaneSight should not hold or move money at launch.
4. **The weak link is not registration, it's what happens after.** A tournament bowler only becomes a LaneSight user if the shot analyzer is good and there's a reason to open the app between events. Instrument that, and give the profile tournament value on day one (results history, average record, squad alerts).
5. **League Mode vs tournaments needs an explicit order.** BUILD_PLAN's post-MVP list puts League Mode (weekly habit) first. DEC-026 puts tournaments (episodic acquisition) first. Both can be right, but the decision should say which comes first and why.

---

## 2. Conflicts with canonical docs

| # | Conflict | Where | Recommendation |
|---|---|---|---|
| C1 | Manager-led acquisition vs "don't lead with management software; create bowler pull first" | DEC-013; Master Context §2, §15, §16 | DEC-026 explicitly supersedes DEC-013 *for tournaments only*. League management stays bowler-pull-first. Update §2 ladder and §16 growth loop. |
| C2 | DEC-004 says League Mode precedes league management. Tournament management is management software, and the PRD places it ahead of League Mode | DEC-004; BUILD_PLAN Post-MVP | State the order in DEC-026. My suggestion: tournaments first (acquisition), League Mode second (habit), since League Mode depends on continuous capture + re-identification, which is a long CV project. |
| C3 | PRD says "after MVP exit," but MVP exit is far out: Stage 1 gate unmet, Seed Dataset not captured, no UI, no cloud | CURRENT_STATE; BUILD_PLAN | Split: discovery now (T-0), build after C-01 (Supabase auth/Postgres) exists. Tournament software doesn't depend on CV, so it *could* run in parallel, but bandwidth is the constraint. Don't let it delay the Stage 1 gate. |
| C4 | Age policy: FEATURE_REVIEW proposes a 13+ gate; tournaments routinely include youth bowlers, and public standings would publish minors' names | FEATURE_REVIEW §2.1, §4.3 | Decide before pilot. Option: directors may register under-13 guests with no LaneSight account and no claim invite; public standings show initials for minors. Needs legal review (COPPA). |
| C5 | Device use in competition: Master Context open question. Tournament bowlers may not be allowed to film or use Audio Coach during the event | Master Context §20b | Don't plan activation around filming *during* tournaments. Activation happens at practice. |
| C6 | Money: side pots and brackets are entry-fee prize pools. Holding or distributing funds raises money-transmission, processor and possibly gaming-law questions in Virginia | PRD TM-017/018/021/025 | New DEC: LaneSight records money, never custodies it, until legal review. Payments via Stripe Connect (director is merchant of record) only after review. |
| C7 | Profile creation as a KPI: if an account is required, registration-to-profile is ~100% by definition | PRD §10 | Measure what's voluntary: claim rate for guests, app install, return visit after the event, first shot analysis within 30 days. |

## 3. Missing requirements
- **Director data import.** Directors have bowler lists and averages from past events (likely in TournamentBowl or spreadsheets). CSV import of bowlers and averages is a switching-cost reducer. P0.
- **Printable outputs.** Lane assignment sheets, score sheets, bracket sheets, payout sheet. Desk staff run on paper when things go wrong. P0.
- **Offline / degraded mode at the desk.** Center Wi-Fi is unreliable (same issue as C-04). Score entry must queue locally and sync idempotently. PRD has idempotency; add explicit offline behavior to TM-009/TM-016.
- **Re-entries.** Many local events allow multiple entries per bowler (separate squads or same squad). Model registration ≠ bowler.
- **Average rules.** Which average counts (highest of last season, current book average, min games), plus a director override with reason. TM-007 captures source; add the rule itself to the versioned rules config.
- **Event-day roles.** A volunteer at the desk needs score entry without seeing payments. Define roles: owner, director, desk, viewer.
- **Spectator/bowler page performance.** Live standings will be hit by everyone at once at squad end. Cache public standings snapshots.
- **Support during live events.** Tournaments are Saturday/Sunday mornings. A solo founder is the on-call. TM-016 should name who answers, how, and the paper fallback.
- **Terms for directors.** Who owns event data, what bowlers see, what LaneSight may contact them about (acquisition consent in TM-015).

## 4. Dependencies and reuse

| PRD need | Existing asset | Notes |
|---|---|---|
| Auth, Apple/Google/email | C-01 Supabase Auth; FEATURE_REVIEW §2.1 | Hard dependency. Tournament web registration needs the same auth as the iOS app from day one, or profiles fork. |
| BowlerProfile, one identity | DEC-003; M5-01 schema | Add guest profiles with claim tokens to the core schema, not a tournament-only table. |
| Organization / tenants | None yet | Design `Organization` generically so LaneSight Leagues and centers reuse it later. Row-level security already used in `schema.sql`. |
| BowlingCenter | Home center lookup (FEATURE_REVIEW §2.1) | One curated center table for both. |
| GameScore | Stage 3 frame/game model (M3-01/02), `ScoreRecord` | Tournament scores are game totals entered by staff. Store as ScoreRecord with provenance = "tournament, director-entered." Frame-level entry is optional and can reuse the M3 scorer. |
| Provenance, no blending | DEC-009 | Tournament results are a separate authority level from practice; profile shows them separately. |
| Center scoring import | `ScoringAdapter` (M3-06, DEC-020) | Same adapter serves TM-023. Don't build twice. |
| USBC | ExternalIdentity; FEATURE_REVIEW §2.3 | Self-entered member ID, labeled unverified, is enough for launch. |
| Stack | FastAPI + Supabase; web/debug tooling | Director console is a CRUD web app. A Next.js + Supabase web app on Vercel is a short path and matches tooling you already run. Rules engine (handicap, standings, brackets, payouts) as a pure, heavily tested module. |

## 5. Minimum set to get a Richmond director to switch
Unverified: I haven't confirmed TournamentBowl's current features or what local directors actually use. Step T-0 confirms this. The reasoning: a director switches only if (a) the event runs with **zero** fallback to the old tool or paper, and (b) something is meaningfully better for them or their bowlers.

**Must have (parity for a typical local singles event):**
- Event setup, squads, lane assignments, check-in (TM-001/003)
- Scratch and handicap singles with configurable rules (TM-002)
- Walk-in registration at the desk in under a minute (TM-006)
- Fast score entry and correction with audit (TM-009)
- Live and final standings, payout calculation and report (TM-010/011)
- Payment status tracking, cash/check/online-elsewhere (TM-012)
- **Brackets: standard 8-person handicap and scratch, multi-entry, auto-fill, payout per bracket, record-only money**
- **High-game / high-series pots: record-only**
- CSV import of past bowlers/averages; exports; printable sheets

**Should be better than the incumbent (reason to switch):**
- Bowlers register and pay attention on their phones; no director data entry for pre-registered bowlers
- Live standings bowlers check from their phone, including after they've left (early squad: "did I cash?")
- Every event becomes a permanent result in each bowler's profile
- Duplicate event as next month's template in one tap

**Not needed to switch:** online payments, doubles/team, multi-round finals, center scoring integration, USBC verification.

## 6. Brackets and side pots in the first public launch?
**Yes, as record-keeping. No money movement.**
- If a director runs brackets today and LaneSight can't, the event still needs the old tool. That kills the switch.
- Bracket math is well-defined (pairings per game, advancement, refunds on unfilled brackets) and fully testable. It's maybe 2–3 weeks, not the hard part.
- The hard part is money: collecting, holding and paying out pot money. Keep that offline (director handles cash; LaneSight prints who is owed what).
- Validate in T-0: which bracket formats each director uses, and whether pots are a deal-breaker. If none of the pilot directors run brackets, defer them.

## 7. Implementation plan

| Milestone | Scope | Depends on | Acceptance criteria | Size |
|---|---|---|---|---|
| **T-0 Discovery** (start now) | Interview 5+ Richmond directors; collect rules sheets, bracket formats, average rules, current tools; sit at one event desk | Nothing | Written rule inventory; ≥3 directors agree to pilot; deal-breaker list confirmed; TournamentBowl feature list verified | S |
| **T-1 Foundation** | Organization + roles + RLS; BowlingCenter; Tournament/Division/Squad; guest profiles with claim tokens | C-01 (auth/Postgres) | Cross-org access test fails closed; a guest can claim and merge into an existing profile without duplicates | M |
| **T-2 Registration** | Public event page, QR, web sign-in, registration + squad pick, desk walk-ins, re-entries, CSV import | T-1 | Phone registration in ≤2 min end to end; walk-in at the desk ≤60 s; import of a real director's list | M |
| **T-3 Scoring + standings** | Rules engine (handicap, ties, payouts), score entry with offline queue, audit, live/final standings, payout report, exports, print views | T-1 | 100% match on a documented edge-case suite built from T-0 rules; replaying inputs reproduces final standings exactly; no lost score after a forced disconnect | M |
| **T-4 Brackets + pots (record-only)** | 8-person brackets, auto-fill, advancement, refunds, high-game/series pots, settlement sheets | T-3 | Matches a director's hand-run bracket sheets on 3 historical events | M |
| **T-5 Supervised pilot** | 3 events: scratch, handicap, multi-squad. Paper fallback rehearsed. Funnel instrumentation | T-2..T-4, privacy terms, age policy | Director confirms no spreadsheet/old tool needed; zero scoring disputes traced to LaneSight; funnel baseline captured | S–M |
| **T-6 Activation** | Profile tournament history, squad-result push, post-event onboarding to shot analysis | iOS app (Stage 7), T-5 | Activation metrics in §8 measured on pilot cohort | M |
| Later | Online payments (after legal), doubles/team, series, center integration, USBC | Legal review; partners | — | — |

## 8. Converting participants without friction
- **Account required to self-register, on web, no app.** Apple / Google / email magic link. One screen to sign in, one to register. Agree with the PRD.
- **Walk-ins never need an account.** Desk registers them; claim link sent only with consent; no claim invite for minors.
- **Make the profile useful on day one, before shot analysis.** Tournament history, cashes, a running "tournament average," upcoming events nearby. This is value the bowler gets without filming anything.
- **Earn the app install with things web can't do well.** Push when your squad's standings change or the event finalizes ("You cashed: 6th, $85"). This matters most to early-squad bowlers who leave.
- **Bridge to shot analysis at practice, not in competition.** Post-event message: "Want to see why your ball went high in game 3? Film a practice session." Tie it to their event.
- **Don't gate standings behind the app.** Spectators and bowlers see public standings on web. The app adds alerts and history.
- **Measure:** guest claim rate, app install within 7 days, return to the app after the event, first shot analysis within 30 days, 90-day retention. Track per director (attribution).

## 9. Proposed changes for review (not committed)

**DECISIONS.md**
- **DEC-026 — Tournament-led acquisition (proposed).** After MVP exit, tournament management is the first platform expansion, before League Mode and league management. Directors are distribution partners; optimize for retained bowlers, not director revenue. Build starts only after T-0 confirms ≥3 pilot directors. *Supersedes:* DEC-013 for tournaments only (league management stays bowler-pull-first). *Refines:* DEC-004 ordering.
- **DEC-027 — LaneSight records tournament money; it does not hold it (proposed).** Entry fees, brackets and pots are tracked and settled on paper/cash by the director until a legal and payments review approves online collection (Stripe Connect, director as merchant).
- **DEC-028 — Shared Organization tenant model (proposed).** One `Organization` + role model for tournament directors now and leagues/centers later; guest profiles + claim tokens live in the core identity schema.
- **DEC-029 — Tournament registration identity policy (proposed).** Self-registration requires a LaneSight account via web (no app required); desk walk-ins don't; minors' policy per FEATURE_REVIEW §4.3 decision.

**BUILD_PLAN.md**
- Add a **Tournament track** (T-0..T-6) under Post-MVP, placed first, with T-0 as an ongoing track that can start now.
- Move Session/League Mode to second in Post-MVP.

**CURRENT_STATE.md**
- Add "Tournament management (DEC-026, proposed)" to Not MVP; add T-0 discovery to Current blockers/discovery.

**LANESIGHT_MASTER_CONTEXT.md**
- §2: insert tournaments into the ladder (Measure → Profile → **Compete** → Coach → Team → …).
- §15/§16: note the tournament exception and the director-led loop.
- §19: add Organization, OrganizationMember, BowlingCenter, Tournament, Squad, Registration, Bracket.
- §20b: add age policy for competitions, money handling, live-event support.

**TOURNAMENT_MANAGEMENT_PRD.md → v1.1**
- Move brackets/pots (record-only) from P1 to public-launch scope; add CSV import, printables, offline score entry, re-entries, roles, minors.
- Replace profile-creation KPI with voluntary activation metrics (§8).
