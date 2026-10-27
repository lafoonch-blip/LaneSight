# LaneSight Coaching — Strategy & Execution Context

Status: PROPOSED / DISCOVERY (not an accepted product decision)  
Version: 1.0  
Last Updated: 2026-10-26  
Owner: Shayne  
Related: `00_CONTEXT/LANESIGHT_MASTER_CONTEXT.md`, `00_CONTEXT/DECISIONS.md`, `01_PRODUCT/BUILD_PLAN.md`, `01_PRODUCT/METRIC_AND_SCORING_LOGIC.md`, `01_PRODUCT/PERFORMANCE_LAB_STRATEGY.md`

## 1. Objective and positioning

Make **LaneSight Coach** the bowling performance platform that helps human coaches set personalized targets, assign training plans, measure progress, and guide athletes between lessons. Coach expertise directs the training; LaneSight provides trustworthy measurements and AI-assisted follow-through.

**For coaches:** “Your expertise. Your coaching philosophy. Your athletes. Powered by LaneSight.”

**For bowlers:** Professional guidance and measurable improvement, integrated with their persistent LaneSight Bowler Profile.

**Product positioning:** Coaching is an integrated pillar of LaneSight, **not a separate app**. A coach–athlete relationship enriches the existing Profile, Sessions, Stats, and Performance Lab experiences.

## 2. Core product principles

1. **Coach-defined targets override default coaching targets** for an athlete's active development plan; they do **not** change measured data or measurement confidence.
2. **Preserve the standard LaneSight Score (0–1000)** and its governing formula/eligibility rules. Custom plans add progress-to-goal views, **not** a separate overall Improvement Score or a rewritten LaneSight Score.
3. Distinguish **measurement → benchmark → evaluation → recommendation**. Track provenance, uncertainty, date, capture setup, and applicable benchmark version.
4. **Coach remains in control**: AI can summarize, draft exercises, and suggest next steps, but cannot silently supersede coach instructions. Coach and athlete can see where recommendations came from.
5. **Trust before breadth**: expose only metrics supported by validated video/sensor/scoring capabilities; display estimated/unavailable where appropriate, never fabricate precision.
6. **Athlete-owned data and permissioned sharing**: explicit coaching connections, revocation, portability, appropriate youth/guardian safeguards.
7. No dependence on scoring-center or sensor integrations for the coaching foundation; incorporate those feeds as they become available.

## 3. Core experiences (prioritized)

| Experience | Coach capability | Bowler experience | Priority |
|---|---|---|---|
| Coach–athlete connection | Invite/connect students; manage permissioned roster | Accept/revoke coach connection | P0 |
| Coach dashboard | Athlete roster, recent activity, plans needing review | See active coach and plan | P0 |
| Custom benchmark profiles | Choose relevant metrics, ranges, weights, and priorities | Compare results to **Coach / LaneSight Standard / Personal Best** | P0 |
| Development plans | Set focus areas, goals, dates, and reusable drill assignments | View and complete assigned practice | P0 |
| Progress tracking | See validated trend versus plan baseline and targets | See progress and milestones | P0 |
| Video review | View clips, frame annotations, select reference delivery | Review annotated feedback / before-after | P1 |
| Coach-directed AI | AI summaries and suggestions constrained by coach plan | Coach-aligned advice between lessons | P1, measurement-dependent |
| Live Coach Mode | Select focus, evaluate short drill series at lanes, save assessment | Immediate focused feedback | P2 |
| Coach program library | Reusable / coach-branded plans | Subscribe to assigned programs | P2 |
| Marketplace / academy | Paid programs, coach discovery, team/multi-coach administration | Find/purchase coaching | P3 |

**Initial release target:** first five P0 experiences, with simple video review if technically feasible. Avoid full messaging, scheduling, billing, and marketplaces until proven necessary.

### Example benchmark record
A coach-defined target should include: athlete ID; metric ID; target value/range; unit; source and accepted confidence; relevant capture/ball/condition context; priority; baseline; start/end dates; author; version; and status. Historical assessments reference the version active at measurement time.

### Coach-directed AI policy
Inputs: athlete history + verified observations + sensor/score provenance + coach focus + active target/plan + assignment history. Outputs: transparent explanations and suggestions for coach review. If a coach's plan conflicts with generic advice, prioritize the plan for development coaching while retaining measurement truth and safety boundaries.

## 4. Target coaches and partnership strategy

Recruit **5–8 founding coaches** for a **90-day pilot** with **5–15 athletes each** (target: 40–120 total). Balance national credibility with local access and one-/two-handed coaching perspectives.

**Initial outreach shortlist (candidates only; current contact/availability and credentials require verification):**
- **Bill Spigner** — video-coaching workflow and competitive product validation.
- **Mark Baker** — brand reach, existing student community, referral potential.
- **Mike Dias** — remote coaching and between-lesson feedback.
- **Joseph Slowinski** — technical mechanics / individualized benchmark methodology.
- **Del Warren** — technical validation and potential training-center connection.
- **Richmond/Virginia independent coaches** — recurring hands-on sessions and repeatable capture validation.

**Partner types:**
- **Founding Coach:** free pilot access in exchange for testing, structured feedback, and selected student onboarding.
- **Technical Advisor:** helps define reliable metrics, drill rubric, and validity criteria; compensation to be negotiated.
- **Brand Ambassador:** referral/promotion relationship only after measured traction and clear terms.

**Outreach angle:** “Your coaching methods, turned into measurable athlete development between lessons.” Lead with time savings and athlete outcomes, **not replacing coaches with AI**. Demonstrate existing functionality accurately and label prototype/planned features.

## 5. Preliminary pricing hypotheses (not approved)

| Audience | Tier | Proposed monthly price | Hypothesis |
|---|---|---:|---|
| Bowler | Free | $0 | Basic profile and coach connection; limited introductory analysis |
| Bowler | Plus | $9.99 | More video analysis / performance history |
| Bowler | Pro | $19.99 | Expanded analysis and advanced performance insights |
| Coach | Starter | $0 | Up to 3 athletes, basic benchmarks and plans |
| Coach | Pro | $39 | Up to 25 athletes, plans, templates, reviews, AI support |
| Coach | Elite | $99 | Up to 100 athletes, advanced analytics and branding |

**Suggested pilot offer:** participating founding coaches get Elite-level access free for 90 days. Test a **15% standard / 25% founding-coach referral share for the first 12 months** of referred *athlete subscription* revenue; do not contract permanent/lifetime commissions at launch.

**Usage economics:** do not bundle unlimited video computation into coach seats. Separate analysis entitlements from read/review access. Proposed starting test allowances: Plus 20/month, Pro 60/month, Coach Pro 30 shared/month, Coach Elite 100 shared/month; finalize only after cloud processing cost and actual use are measured. Coach and student should be able to exchange plans and review existing results without both buying premium subscriptions.

**Later, not MVP:** paid coach-created development programs / coaching marketplace. Test ~20% platform fee as a hypothesis net of transaction fees and inference costs.

## 6. Pilot outcomes and measurement

**Pilot exit criteria (targets to validate):**
- 75% of coaches use the product weekly.
- 60% of enrolled athletes complete at least two sessions during pilot.
- 70% of coaches say progress visibility adds value.
- 50% of coaches indicate credible willingness to pay for a defined paid tier.
- Core coach-assessed metrics meet explicit accuracy/confidence thresholds before being shown as trustworthy development evidence.
- Capture and onboarding workload is acceptable to working coaches.

Measure also: coach-to-athlete invitation acceptance, time to first benchmark, assigned practice completion, review time per athlete, free-to-paid conversion, retained athletes, referral volume, and per-analysis cloud cost.

**Critical dependency:** Current video/calibration issues make accuracy the launch gate. Engage coaches early to test product direction, but do not commercialize unsupported biomechanics metrics. Coach assessments can use manual observations and annotated footage when automatic metrics are unavailable.

## 7. High-level execution checklist

1. **Finalize coaching strategy** — agree positioning, foundational capabilities, partnerships, and pricing hypotheses.
2. **Create coach UX mockups** — dashboard, athlete profile, benchmark editor, plan builder, and bowler-facing goal comparison using the v3.7 Figma system.
3. **Build coach target list** — 15–20 national + Virginia prospects, with verified channels and tracking.
4. **Prepare partnership pitch** — concise overview, honest product demo, pilot ask, and clear incentives.
5. **Begin discovery outreach** — contact 5–10 prospects; gather objections and prioritize workflows.
6. **Establish founding-coach pilot** — enroll 5–8 coaches, define consent/feedback protocol and expected participation.
7. **Build coaching P0 MVP** — role relationships, benchmark versioning, development plans, progress comparisons.
8. **Pilot and validate** — evaluate coach/athlete usage, data quality, and measurable usefulness.
9. **Finalize pricing** — test willingness to pay, compute allowance economics, and commission structure.
10. **Launch and expand** — case studies, coach referrals, next-phase AI/video, institutional partnerships.

**Immediate recommendation:** run steps 1–5 in parallel with the ongoing shot/form metric validation program; build commitments and a credible test cohort before advanced AI coaching.

## 8. Proposed phased release plan

- **Phase 1 — Foundation:** coach accounts/permissions, athlete roster, benchmark profiles, plans, progress.
- **Phase 2 — Coaching workflow:** annotated video, reference clips, reusable assignments, before/after views.
- **Phase 3 — Intelligence:** confidence-aware coach-directed AI, periodic review summaries, live focused drill assessments.
- **Phase 4 — Ecosystem:** coach marketplace, paid programs, academy/team management, wider partnerships.

## 9. Decisions still required

- Is the initial coach offering a dedicated top-level navigation area or a role-switch dashboard?
- Which **validated** shot/form metrics may be benchmarked at P0, and which require manual observation?
- Can one athlete work with multiple active coaches, and how are conflicting targets resolved?
- Who pays for analyses submitted specifically for coach review?
- What consent, retention, and youth-account requirements apply to shared videos?
- Exact usage limits and prices following pilot unit-economics testing.

**Governance:** This is a strategy/context proposal; it does not revise `DECISIONS.md` or claim these features/prices are approved. Once decisions are made, append appropriate new DEC entries, and update `CURRENT_STATE.md`, `BUILD_PLAN.md`, and the applicable feature/metric docs in lockstep. Never rewrite decision history.
