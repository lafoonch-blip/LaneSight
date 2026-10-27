# LaneSight — Bowling Industry Intelligence & Opportunity Monitoring Strategy
Status: PROPOSED OPERATING STRATEGY  
Version: 1.0  
Last Updated: 2026-10-26  
Owner: LaneSight  
Authority: Strategy context; subordinate to `00_CONTEXT/DECISIONS.md` and `00_CONTEXT/CURRENT_STATE.md`

## 1. Purpose
Build an always-on, ethical bowling industry intelligence capability that turns external developments into product, distribution, integration, partnership, and content opportunities for LaneSight. This is **not** a generic sports-news feed. Every surfaced development should answer: **What happened? Why does it matter to LaneSight? What should we do?**

Align with the canonical strategy: hardware-agnostic Bowler Profile; **Measure → Profile → Coach → Team → Connect → Manage → Platform**; serious league/tournament bowlers and coaches first. Never imply unverified metrics, API access, endorsements or partnerships. Accurate video analysis remains the credibility gate before major promotion.

## 2. Monitoring coverage and source tiers
| Watch | Sources to monitor | Opportunity triggers |
|---|---|---|
| Governing bodies / tournaments | PBA, PBA50, PBA regional/ELITE, PWBA, USBC, BPAA, official tournament schedules and rule bulletins | Rules that affect filming/technology, event sponsorships, tournament activations, player access |
| Broadcasting / media | BowlTV, PBA broadcast partners, Bowlers Journal, bowling podcasts and reputable industry publications | Media integration, co-marketing, broadcast statistics, advertising placements |
| Ball and sensor ecosystem | Storm/Roto Grip/900 Global, Brunswick/Hammer/DV8/Radical, Motiv; Ruby, Specto and emerging measurement tools | Device data partnerships, ball launches, measurement interoperability, creator content |
| Scoring / center platforms | QubicaAMF, Brunswick scoring systems, LaneTalk, LeaguePals, center vendors | Authorized game/pinfall data integrations, pilot centers, API programs, competitive positioning |
| Creator / coaching ecosystem | Established YouTube bowling educators, emerging micro-creators, independent coaches, Instagram/TikTok, podcasts | Product demonstrations, coach pilots, creator affiliate partnerships |
| Community demand | r/Bowling and other relevant Reddit communities, public creator comments, bowling forums | Unmet needs, feature requests, workflow pain points, beta candidates |
| Competitor / adjacent products | LaneTalk, Specto, other video-analysis, coaching, scoring and performance platforms | Feature launches, partnerships, pricing shifts, differentiation gaps |

**Source rules:** Official primary statements are preferred for rules, dates, and products. Community discussion is a demand signal, not proof. Verify key claims against primary sources; record published date and event date separately. Respect platform terms, access controls, rate limits, robots directives and copyright.

## 3. Delivery cadence (tasks established 2026-10-26)
### Daily — Bowling Industry Opportunity Watch
- Scheduled every morning at approximately **8 a.m. America/New_York**.
- Conditional alert: notify **only** for genuinely new, high-signal/actionable developments, not generic match scores or recycled stories.
- Include: headline, exact date, 1–2 source links, category, relevance, urgency, recommended next action.
- Deduplicate by canonical source URL + event/entity + substantive change. Escalate meaningful updates on previously tracked items.

### Weekly — LaneSight Weekly Industry Brief
- Scheduled Mondays at approximately **8 a.m. America/New_York**.
- Top **five** verified developments; competitive/technology changes; creator and coaching movements; partnership leads; top **three** recommended actions ranked by expected value and effort.
- Link to earlier alert/opportunity when continuing a story. Avoid asserting that a lead is a confirmed opportunity or relationship.

These are ChatGPT scheduled monitoring tasks, **not** an implemented ingestion platform or GitHub-writing automation. Execution quality and available sources must be validated. GitHub remains the authoritative documentation source; automated outputs must not silently overwrite governance documents.

## 4. Opportunity classification, scoring and response
**Types:** Product/feature, integration/API, distribution/channel, creator/influencer, coaching, tournament/event, regulatory/policy, competitor threat, user insight.

Use a proposed **0–100 opportunity score**:
- Strategic fit (0–25): supports Measure/Profile/Coach/Team and target customers.
- User/revenue impact (0–25): plausible acquisition, activation, retention or monetization benefit.
- Timing/urgency (0–15): event/application/partner window.
- Feasibility (0–15): build effort, costs, permissions, data reliability.
- Evidence/confidence (0–10): primary confirmation and source quality.
- Differentiation (0–10): defensible advantage vs existing solutions.

**Routing:** ≥80 = same-day action recommendation; 60–79 = weekly priority; 40–59 = watchlist; <40 = archive unless risk-critical. Risk-critical rule/privacy/competition items can override score.

Each prospect must have an explicit **owner, next action, due date, status, and decision rationale**. No implicit commitment of spend or outreach.

## 5. Opportunity registry — proposed schema
`opportunity_id, discovered_at, event_date, title, summary, category, source_urls[], entities[], evidence_level, strategic_fit, impact, urgency, feasibility, confidence, differentiation, score, priority, owner, next_action, due_date, status, estimated_cost, expected_outcome, related_opportunities[], last_checked_at`

Lifecycle: `new → triaged → researching → outreach_planned → contacted → evaluating → approved → executing → measured → closed` (with `watchlist` and `rejected` side paths).

Start with a lightweight versioned Markdown/CSV registry or private database; only build a searchable dashboard when volume warrants it. Never store scraped private personal data or nonpublic information without authorization.

## 6. Proposed AI-agent workflow
1. **Collector:** gather permitted RSS, official announcements, public web updates, authorized APIs and selected public discussions.
2. **Verifier:** de-duplicate, confirm dates and claims, distinguish official news from commentary/rumor, retain provenance.
3. **Opportunity Analyst:** map developments to LaneSight product, GTM and partnerships; score with the above rubric.
4. **Campaign/Partnership Planner:** propose educational content, outreach, promotion or feature experiments; draft only.
5. **Reporting Agent:** prepare daily exception alerts and weekly intelligence briefs.
6. **Human approver:** validates priorities, public-facing claims, spending, outreach and publishing.

**Controls:** No autonomous spam, bot impersonation or fake endorsements; no unauthorized crawling/APIs; influencer disclosures; no publishing without approval; no presenting synthetic metrics as measured. Promotional content involving filmed people needs consent/rights review. Any product claims about speed, rev rate, trajectory or coaching must respect metric confidence/unavailable gates and validation status.

## 7. Examples of high-value triggers
- Scoring-platform developer program or documented data access → assess `ScoringAdapter` and authorized score/pinfall ingestion.
- PBA/USBC filming or technology rule changes → update capture guidance and tournament positioning.
- New creator series on rev rate / launch angle → propose educational collaboration using **verified** LaneSight demonstrations.
- Sensor vendor offers SDK or export → assess `SensorAdapter`, source provenance and shot synchronization.
- New regional event or coaching clinic → explore opt-in beta demos and referral partnerships.
- Competitor releases video/form analytics → benchmark differentiators and update positioning.

Initial watchlist: PBA/PWBA/USBC/BPAA announcements; BowlTV and regional event schedules; QubicaAMF/Brunswick/LaneTalk scoring/data; Specto and sensor makers; bowling educators and coaches. **Do not claim commercial interest, access, or a partnership without direct verification.**

## 8. Success metrics and reporting
- Intelligence: sources covered, verified items/week, duplicate rate, alert precision, false-positive rate, time-to-detection.
- Opportunity: qualified opportunities/month, actions taken, partner responses, pilots initiated, time from detection to action.
- Growth: attributed waitlist signups, first analyzed sessions, 30-day retention, coach/creator referred users, paid conversion.
- Economics: monitoring/tool cost, cost per qualified opportunity, partnership acquisition cost and contribution margin.
- Quality: citation/source coverage, corrections, stale-data rate, unsubstantiated-claim rate.

Weekly reports should clearly distinguish **facts**, **hypotheses**, **recommended action**, and **open questions**.

## 9. Phased implementation
**Phase 0 — now (Oct–Nov 2026):** operate daily exception alerts and weekly brief; compile source registry; record top opportunities; validate signal quality after four weeks.
**Phase 1 — pre-beta:** formalize creator/coach watchlists, tags, dashboard/registry, approved outreach templates and attribution links.
**Phase 2 — beta:** connect opportunity triage to beta recruitment, coach partnerships, product backlog and experiment tracking; monitor cohort conversion.
**Phase 3 — launch/growth:** add authorized feeds, monitoring observability, regular competitor feature matrix, creator CRM and measured sponsorship/affiliate experiments.

Go/no-go for expanding automation: consistent high-value, verifiable alerts; identified owner for follow-up; clear revenue or learning case; compliant source access.

## 10. Ownership and integrations
- Product owner: prioritization, partnership/outreach approval, spending and external claims.
- AI monitoring: discovery, synthesis, scoring suggestions and periodic briefs.
- Engineering: approved source ingestion, secure storage, dashboards and vendor integration evaluation.
- Marketing: content calendar, creator pipeline, attribution and test design.

Cross-reference canonical documents: `00_CONTEXT/LANESIGHT_MASTER_CONTEXT.md` (GTM and integrations), `00_CONTEXT/CURRENT_STATE.md` (accuracy/readiness), `00_CONTEXT/DECISIONS.md` (authority), `01_PRODUCT/BUILD_PLAN.md` (implementation gate). This document proposes an operating strategy; it does **not** alter accepted DEC entries.
