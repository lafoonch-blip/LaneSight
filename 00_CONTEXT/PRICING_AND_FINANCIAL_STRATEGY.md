# LaneSight — Pricing, Financing & Unit Economics Strategy
Status: PROPOSED — planning assumptions, not approved pricing or observed costs  
Version: 1.0  
Last Updated: 2026-10-26  
Owner: Shayne  
Related: `AGENTS.md`, `00_CONTEXT/LANESIGHT_MASTER_CONTEXT.md`, `00_CONTEXT/CURRENT_STATE.md`, `00_CONTEXT/DECISIONS.md`, `01_PRODUCT/BUILD_PLAN.md`  

## 1. Purpose and operating principle

Build LaneSight as a capital-efficient, subscription-led bowling intelligence business that expands only when customer traction, product quality, and unit economics justify the next expenditure. This document is a **commercial planning proposal**. No price, spend cap, feature entitlement, or financing amount is an accepted product decision until formally approved and, where appropriate, recorded as a new entry in `DECISIONS.md`.

**Principle:** revenue funds growth; growth must not depend on speculative future revenue. Maintain an affordable free entry point for the Shot Analyzer → Bowler Profile → coaching/league habit loop, while charging for persistent performance insight and premium usage. The differentiated product is the unified Bowler Profile and actionable longitudinal analytics, not merely expensive video inference.

**Canonical product sequence:** Measure → Profile → Coach → Team → Connect → Manage → Platform. Keep approved architecture and metric-accuracy decisions authoritative. Do not advertise future sensor/scoring/PBA features as generally available before permissions and validation.

## 2. Pricing hypotheses (USD)

| Tier | Proposed monthly | Proposed annual | Intended audience | Initial release |
| --- | ---: | ---: | --- | --- |
| Free | $0 | $0 | Try LaneSight, build profile and arsenal | Launch |
| Performance | $9.99 | $99 | Serious league/tournament bowlers | Launch when billing/quality ready |
| Elite | $19.99 | $199 | Heavy video and advanced analysis users | Later, gated on differentiated capabilities |
| Coach | $39.99 | $399 | Independent coaches with managed clients | Later pilot; capacity-based pricing TBD |

**Entitlement hypothesis** (not launch promises):

| Entitlement | Free | Performance | Elite | Coach |
| --- | --- | --- | --- | --- |
| Saved profile, basic stats, arsenal | Yes | Yes | Yes | Clients, subject to consent |
| Trend history | 30-day window | Extended/unlimited metadata history | Extended/unlimited | Authorized client trends |
| Included video analyses/month | 2 | 15 | 40 | Pooled usage, exact allowance TBD |
| Shot/Form analysis | Selective preview | Both when validated | Both + premium features when validated | Client-specific coaching workflows |
| AI recommendations | Basic | Personalized | Advanced where validated | Custom coach benchmarks |
| Sensor/scoring integrations | Product availability and rights dependent | Same | Same | Same |
| PBA comparisons | Not promised | Not promised | Future only, subject to rights and reference data | Future only |

**Controls:** credit applies to defined completed analysis jobs, with transparent handling of infrastructure failures and user errors; disclose expiration, carryover, cancellation, annual renewal and refund rules clearly. Avoid permanently free unlimited compute. Make analytics/profile value useful without repeated video uploads. Do not claim unlimited raw video retention.

**Founder offer:** test $6.99/month Performance for the first ~100 paying users; duration/eligibility and impact on margins must be approved before public advertising. Avoid irreversible lifetime entitlements. Consider add-on pack of five analyses at $4.99 only after measuring variable costs and payment-channel rules.

**Initial SKU recommendation:** only Free and Performance in the first paid release. Do not launch Elite/Coach as paid SKUs until features justify separation and relevant beta evidence exists.

## 3. Beta and rollout finance gates

| Phase | Illustrative total users | Illustrative paying users | Illustrative MRR | Business purpose / gate |
| --- | ---: | ---: | ---: | --- |
| Controlled private beta | 25–50 | 0 | $0 | Validate quality, instrumentation, completion/retry rates and true cost per successful analysis |
| Public beta | 100–300 | 20–50 | ~$200–500 | Test conversion, pricing and credits after payment/consent readiness |
| Commercial launch | 500–1,000 | 100–200 | ~$1,000–2,000 | Test cost recovery, retention and support burden |
| Early growth | 2,500–5,000 | 500–1,000 | ~$5,000–12,000 | Expand only when margins and service reliability sustain it |
| Expansion | 10,000+ | 2,000+ | $20,000+ | Invest in coaches, centers, partnerships and B2B only with validated demand |

All user, payer, conversion and revenue counts are **illustrative scenario milestones, not forecasts**; price mix, discounts and app-store fees may materially change realized cash.

**Gate to charge:** independently verifiable metric quality; clear unsupported/unavailable states; billing/refunds tested; entitlement enforcement; transparent data retention; privacy and coach consent; support coverage; infrastructure budgets; production SLOs.

**Gate to scale paid acquisition:** confirmed cohort retention, cost per acquired paying customer (CAC), contribution margin by tier, abuse prevention, and a credible CAC payback window.

## 4. Technology and variable-cost model

Existing direction: native SwiftUI, Supabase/Postgres + Auth + storage, FastAPI/Python vision inference hosted on Google Cloud Run, Vercel for web/admin. Actual provisioned services must be discovered in production billing dashboards, not inferred from architecture docs. Avoid double-counting storage/network included in a vendor plan.

**Illustrative monthly operating ranges (USD; not vendor quotes):**

| Service group | Private beta | Early commercial | Growth |
| --- | ---: | ---: | ---: |
| Supabase | $25 | $25–50 | $50–150 |
| Cloud Run processing | $0–25 | $25–100 | $100–500 |
| Vercel | $20 | $20 | $20–60 |
| Object storage/egress | $0–10 | $10–50 | $50–250 |
| AI API consumption | $10–30 | $30–150 | $150–500 |
| Observability | $0–10 | $0–25 | $25–100 |
| Notifications/email | $0–5 | $5–15 | $15–50 |
| **Illustrative total/month** | **$55–100** | **$145–410** | **$410–1,610** |

These envelopes **exclude** app-store/payment fees, legal, tax, customer support labor, marketing, accounting, security, and founder compensation. Cloud Run free allowances must be calculated using the actual region, CPU/memory, concurrency, request duration, networking, and any always-on resources; do not assume a blanket count of free video analyses. Confirm vendor pricing directly before implementation.

### 4.1 Per-analysis measurement contract

For each `analysis_job`, record:
- `user_id` (pseudonymous in analytics), `tier`, `billing_channel`, credit consumption;
- submitted/video-trimmed length, FPS, resolution, bytes ingress, retained bytes and expiry;
- Cloud Run instance, CPU seconds, GiB seconds, cold start, retries, queue latency, worker duration;
- inference model/version, API/token charges (if used), storage/egress, monitoring cost allocation;
- job outcome (complete/partial/unavailable/fail), error taxonomy, quality gate and refund/recredit outcome;
- estimated attributable unit cost and actual cloud invoice reconciliation bucket.

Track **cost per submitted job**, **cost per successfully completed job**, **p50/p95 latency**, retry multiplier and per-user contribution margin. Separate internal/no-charge evaluation jobs from customer-paid work. A 30/60/120/240-fps test matrix must include short/long, failure/retry and multiple capture perspectives.

**Initial unverified sensitivity assumption:** $0.05–$0.20 *fully attributable variable cost* per submitted video analysis; center-case $0.10. Do not present this as an observed LaneSight benchmark.

| Analyses/month | Cost at $0.05 | At $0.10 | At $0.20 |
| ---: | ---: | ---: | ---: |
| 100 | $5 | $10 | $20 |
| 1,000 | $50 | $100 | $200 |
| 5,000 | $250 | $500 | $1,000 |
| 10,000 | $500 | $1,000 | $2,000 |
| 50,000 | $2,500 | $5,000 | $10,000 |

**Capacity/cost guardrails:** per-user monthly credits, per-job file limits, concurrency controls, queue backpressure, idempotent jobs, retry budgets, short raw-footage retention consistent with privacy policy, job cancellation, per-tier quotas, suspicious usage alerts, cloud billing budgets and incident kill-switches. Cloud budgets are typically alerts, not hard cost shutoffs; enforce caps in the application/queue.

## 5. Subscription unit economics

Use **net recognized revenue** after discounts, refunds, applicable taxes and platform commissions; model App Store and web separately. Confirm Apple program eligibility and actual commissions before assuming a 15% rate. Include RevenueCat or similar subscription software charges only if adopted, with current verified pricing.

Unit economics by tier/month:
- Gross billings = subscribers × advertised price adjusted for annual-plan accrual and discounts.
- Net revenue = gross billings − taxes/refunds − app-store/payment-provider fees − subscription tooling fees.
- Variable COGS = successful and unsuccessful analysis compute + inference + variable storage/network + variable customer support/communications.
- Contribution = net revenue − variable COGS.
- Contribution margin = contribution / net revenue.
- CAC payback months = CAC / monthly contribution per acquired paying subscriber.
- LTV = monthly contribution per subscriber × expected paid lifetime; use churn-cohort sensitivity rather than assuming permanence.

**Illustrative exposure at $0.10/analysis:** Performance's 15-credit allowance implies up to $1.50 in analysis expense per fully-utilizing subscriber; Elite's 40 implies up to $4.00. This is *before* payment fees, storage, failed runs, support and other overhead. Actual usage distribution matters more than allowance maximum alone. Reprice/adjust credit limits if heavy-user p90/p95 costs erode margins.

**Target:** >=70% sustainable gross margin once measured, and positive contribution by paid cohort. Track free-user subsidy separately. Annual plans create cash sooner but also a future service obligation; do not treat all prepaid cash as instantly earned revenue.

## 6. Scenario planning (illustrative, not forecasts)

Assume $11/month blended *gross subscription list-price-equivalent* across paid users; costs below are hypothetical operating envelopes and do not constitute all-in net profit.

| Metric | Conservative | Moderate | Aggressive |
| --- | ---: | ---: | ---: |
| Registered users | 1,000 | 5,000 | 15,000 |
| Paying conversion | 10% | 15% | 20% |
| Paying subscribers | 100 | 750 | 3,000 |
| Gross MRR equivalent | $1,100 | $8,250 | $33,000 |
| Annualized gross run-rate | $13,200 | $99,000 | $396,000 |
| Assumed recurring operating costs/month | $400 | $2,500 | $9,000 |
| **Illustrative amount before omitted costs** | **$700** | **$5,750** | **$24,000** |

**Warning:** the bottom row is not GAAP profit, net income or founder take-home. Real outcomes require model inputs for store fees, customer-support staffing, R&D, professional services, marketing, tax and refunds. The $1,000 MRR lean break-even *aspiration* refers to cash infrastructure coverage, not economic break-even inclusive of all company costs.

### Required 24-month financial model tabs

1. **Assumptions:** SKU/tier prices, taxes, promo rate, paid conversion, monthly active users, monthly churn/retention, annual vs monthly mix, geographic payment channels.
2. **User cohorts:** signups → activated → retained → paid by acquisition month, trials, upgrades/downgrades/cancellations.
3. **Analysis workload:** jobs/user by tier, resolution/FPS, failure/retries, retention and storage lifecycle.
4. **Infrastructure:** fixed vendors + marginal Cloud Run/AI/storage/egress vs usage, reserved capacity, alerts.
5. **Revenue:** gross bookings, net MRR/ARR, deferred annual revenue, payment fees, refunds.
6. **Operating expenses:** legal, accounting, security, tools, support, marketing, founder/contractor costs.
7. **Cash flow:** opening cash, prepaid receipts, tax reserves, operating outflows, ending cash/runway.
8. **Dashboard and scenarios:** downside/base/upside, cohort economics, break-even, cash needs and sensitivity sweeps.

## 7. Financing and reserves

**Proposed funding posture:** bootstrap rather than dilute equity early. Establish a separate LLC/business bank account and maintain accounting and tax reserves. Coordinate with the legal strategy for entity formation, trademark, domain and any patent counsel. Professional filing costs are jurisdiction- and scope-dependent.

**Proposed initial founder-funded reserve:** $7,500, subject to personal liquidity and actual formation/legal estimates:

| Allocation | Reserve |
| --- | ---: |
| Formation/trademark/legal planning | $2,500 |
| Technology operations | $1,500 |
| Beta acquisition / marketing | $1,000 |
| Beta incentives | $500 |
| Contingency | $2,000 |
| **Total** | **$7,500** |

This is a cash allocation **proposal**, not a required capital call or proof that patent filings fit within the budget. Any patent drafting/prosecution requires a separate quote and decision. Minimum reserve policy: strive for at least six months of expected baseline infrastructure spend plus committed obligations; reforecast monthly.

### Funding escalation triggers

Prioritize reinvested subscription revenue. Explore non-dilutive partnerships or financing only after evidence of repeatable unit economics, or if a uniquely attractive integration contract requires capital. Consider equity funding only for a clear opportunity that cannot be responsibly financed through retained earnings.

## 8. Reinvestment policy and approval controls

Once variable operating costs, contractual obligations and tax provisions are covered, **proposed** allocation of discretionary operating cash: 35% product/R&D, 25% acquisition, 25% reserve, 15% owner distributions (prefer retaining distributions in earliest phases). Not a rigid rule; apply cash flow, legal/tax and runway constraints first.

Spending approvals:
- No new recurring vendor without owner, cost center, usage forecast and cancellation owner.
- Set hard **application quotas** for compute, storage retention and API requests; vendor billing alerts at 50/80/100% of budget.
- Require positive projected contribution margin for every paid SKU and sensitivity to p95 usage.
- Expand marketing only after credible CAC/payback and 30/60/90-day retention evidence.
- Separate beta courtesy credits from paid/consumed entitlements.
- Reconcile estimates with invoices and audit unusually expensive jobs weekly during launch.

## 9. Financial & growth observability

Integrate with LaneSight production monitoring and AI operations plans. Dashboard panels:
- **Growth:** registrations, activation, MAU/WAU, paid conversion, funnel drop-off, referral conversion.
- **Revenue:** gross/net MRR, ARR, ARPPU, annual prepayments, refunds, delinquent payments, churn, net revenue retention.
- **Unit cost:** cost/job (submitted/successful), usage by FPS/length/tier, failed retry burn, cloud invoices vs attributed compute, raw storage growth and data egress.
- **Margins:** margin by tier, free-tier subsidy, high-usage cohorts, discount cohorts, realized vs target gross margin.
- **Acquisition:** CAC by channel, paid activation, CAC payback, cohort LTV.
- **Cash:** monthly fixed/variable spend, cash burn, bank balance, obligations, runway and budget variance.
- **Reliability:** p50/p95 analysis turnaround, job fail/partial rates, billing-entitlement errors, vendor outages.
- **Privacy:** deleted-video SLA, non-user footage handling and retention policy adherence.

Suggested agents (human-owned approvals): daily spending/anomaly watcher, weekly cohort/economics analyst, weekly unit-cost regression analyst, monthly pricing/retention analyst, monthly runway and cost forecast. Agents may recommend actions; they should not autonomously change customer billing, subscription prices, large spending limits or production resource policies.

## 10. Critical validation experiments

**Before monetization:**
1. Benchmark Cloud Run job cost over representative real bowling video, including retries and failed jobs; reconcile estimate to billed spend.
2. Instrument credits, job accounting, footage retention/deletion and transactional attribution.
3. Confirm Apple subscription compliance/commission and web-purchase eligibility; verify any third-party subscription platform pricing.
4. Run controlled customer research for $9.99 vs alternative entry pricing and value of stats/profile vs video credits.
5. Test 2/15/40 monthly credit design against observed user need; observe suppressed engagement from limits.
6. Validate willingness-to-pay and workflows with several coaches separately from consumer pricing.
7. Establish guardrail that free-tier variable cost remains within a deliberate acquisition budget.
8. Confirm permissions for PBA comparisons, sensor data and scoring systems before assigning paid-tier value.

**Decision checklist:** actual cost per successful analysis? peak jobs/week? average/p90 jobs per engaged bowler? paid tier gross/contribution margins after channel fees? 30/60/90-day retention? conversion and annual-plan uptake? refund/chargeback rate? revenue required for the next infrastructure tier?

## 11. Immediate implementation backlog

**P0 — pre-beta**
- Cost-tag every analysis job; create budget/usage alerts and app-enforced limits.
- Define raw video lifecycle and storage/egress measurement.
- Complete cost benchmark under current Cloud Run configuration; record baseline invoice evidence.
- Establish company budget/cash ledger and six-month reserve forecast.

**P1 — before public paid beta**
- Implement entitlement/credit ledger with refunds/idempotency and billing webhooks.
- Validate pricing and founder discounts with real users.
- Instrument payments, subscriptions, churn and cohort funnel.
- Ship financial and operations dashboard with alerts and monthly review cadence.

**P2 — post-product-market validation**
- Optimize expensive video paths with evidence; evaluate newer processing architecture.
- Pilot coach economics and client seat/pool caps.
- Pilot B2B licensing/partner monetization and only then consider broader paid acquisition.

## 12. Open decisions (do not silently promote to accepted)

- Exact initial SKU(s), monthly/annual prices, founder offer length and eligibility.
- Included analyses, definition of billable job, carryover, add-on purchase rules.
- Annual billing channel and App Store purchase requirements.
- Gross-margin floor, maximum free-tier variable subsidy/user, CAC payback ceiling.
- Initial reserve amount and the separate legal/IP budget.
- Data retention policy, refund and credits policy, coach seat allowance.
- Timing of Elite, Coach, integrations and comparison feature commercialization.

**Change control:** Upon approval, add new numbered entries to `00_CONTEXT/DECISIONS.md` (append-only; never rewrite history), then update referenced canonical strategy/plan docs with bumped Version and Last Updated fields. Mirrors are read-only until resynced from GitHub.
