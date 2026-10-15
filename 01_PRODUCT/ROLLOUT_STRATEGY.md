# LaneSight Rollout Strategy: pay as you grow
Status: DRAFT (for Shayne's review)
Version: 1.0
Last Updated: 2026-10-15
Owner: Shayne
Builds on: `COST_PLAN.md` v1.0, DEC-017/019, proposed DEC-026/027

---

## 1. Principle
**Ship cheap features free, meter expensive features, and unlock each new cost only when revenue already covers it.**

- Most of LaneSight costs almost nothing to run: profile, arsenal, stats, manual entry, adjustments, tournament registration and scoring. These can be free, forever, and drive growth.
- One thing costs real money: **cloud video analysis** (plus raw video storage). That is the paid product, or it's capped.
- Fixed costs (pen test, Supabase Team, online payments, integrations) wait until a paying customer or a revenue trigger justifies them.

## 2. Cost class of every feature

| Class | Features | Cost to run | Rollout rule |
|---|---|---|---|
| **Near-zero** | Profile, arsenal, oil pattern library, manual score/pin entry, game stats, trends, adjustments rules engine, spare targeting, sensor manual entry + variance, tournament registration/scoring/standings/brackets (record-only) | Database rows; < $0.01/user/mo | Free tier, unlimited |
| **Metered** | Video shot analysis, replay image, heatmap, raw video retention, replay video render/share, moving-camera analysis, HFR deep analysis (axis/PAP) | ~$0.005/clip at target; storage per GB | Free tier capped; paid tier unlimited (or high cap) |
| **Fixed step-ups** | Supabase compute upgrades, Team plan, pen test, online tournament payments, center/USBC integrations, Android | $100s–$1,000s | Unlocked by triggers in §5 |

## 3. Phases

### Phase 0 — Validate locally (now → Stage 1 gate)
- Analysis runs on your Mac via the local runner. **Cloud cost: $0.**
- Spend only on validation: sensors, lane time, Specto, mounts (COST_PLAN §7).
- Do the cost work now, while it's free: measure seconds per clip and optimize (Runner Milestone 4). Every second removed here is money saved for the life of the product.
- Run T-0 tournament director discovery (interviews only, $0).

**Exit:** Stage 1 gate passes; you know real seconds-per-clip.

### Phase 1 — Private beta (10–25 bowlers)
- iOS app via TestFlight (Apple Developer $99/yr is the only required fee).
- **Supabase free tier** for auth/DB (keep it awake with the beta's daily use or move to Pro at $25 if pausing bites).
- **Video in Cloudflare R2 free tier** (10 GB), raw video deleted after 7–14 days in beta.
- **Analysis: async queue, scale-to-zero GPU** (Modal per-second, no idle cost). Results in minutes, not seconds; that's fine for beta. No always-on servers.
- Hard spend caps on every provider (Supabase spend cap on, GPU budget alert, per-user daily clip limit).
- Legal minimum before outside users: Terms + Privacy Policy covering video (~$1.5–5k, or templates + a short lawyer review).

**Budget:** ~$0–75/month + one-time legal.
**Exit:** bowlers return weekly for 4+ weeks; cost per clip measured in production; a willingness-to-pay test answered (ask beta users to pre-pay or commit).

### Phase 2 — Public launch, freemium
- **Free:** everything near-zero, plus a capped number of video analyses per month (e.g. 20–30 clips) with async results and 30-day raw video retention.
- **Paid (subscription via App Store):** unlimited or high-cap analysis, priority (faster) processing, longer video retention, replay video export, ball comparison history, deep analysis when built.
- Tournament pilot (T-5) runs here: entirely near-zero cost, money record-only (proposed DEC-027). Needs insurance + minors review before the first event.
- Stay on Supabase Pro ($25) and scale-to-zero GPU. Upgrade compute only when the database is the bottleneck.

**Budget:** ~$100–500/month, mostly GPU tied directly to usage.
**Rule:** free-tier GPU spend is a marketing cost with a fixed monthly ceiling. When it hits the ceiling, the cap tightens, not the budget.

### Phase 3 — Ramp (revenue-funded)
Each item below unlocks when its trigger is met (§5), not on a schedule:
- Faster "instant at-lane" results (warm GPU containers or on-device Stage A)
- Bigger database compute
- Online tournament payments (Stripe, director as merchant of record, no platform fees)
- Pen test and security review (required before payments or center deals)
- Moving-camera and HFR deep analysis as paid features
- Android
- Center/USBC integrations, Supabase Team (only when a B2B customer requires it)

### Phase 4 — Scale
- Move Stage A analysis on-device (Core ML) to remove most GPU cost per user.
- Negotiate reserved/cheaper GPU once usage is steady (per-second serverless is best for bursty, low volume; reserved wins at steady high utilization).

## 4. Keeping the metered cost small from day one
- **Async by default, instant as a paid perk.** Queued jobs batch well and never need warm (idle-billed) GPUs.
- **Retention tiers.** Delete raw video after 30 days on free; keep derived data (trajectory, metrics, replay image) forever. It's kilobytes.
- **Process only what's needed.** Run Stage A (speed, pins, boards, entry) for every clip; run Stage B (rev rate, replay video) on demand or for paid users.
- **Reject bad clips before GPU.** The capture-tier check (DEC-023) runs on the phone and refuses unusable video before upload.
- **Per-user and global spend caps.** No single user or bug can run up the bill.

## 5. Spend triggers

| Unlock | Monthly cost added (≈) | Trigger |
|---|---|---|
| Supabase Pro | $25 | Beta starts, or free-tier pausing disrupts users |
| Larger DB compute | $15–60 | DB CPU/RAM > 70% sustained, paid by existing MRR |
| Warm GPU for instant results | $100–600 | Paid subscribers ≥ ~100 and they ask for speed |
| Insurance + minors legal review | $3–7k/yr + one-time | Before the first tournament pilot |
| Online tournament payments + pen test | $5–20k one-time | ≥3 active directors ask for it **and** MRR covers the pen test within ~6 months |
| Supabase Team | $599 | A center or league customer requires SOC 2/SSO and pays for it |
| On-device analysis engineering | Your time | GPU spend > ~20% of revenue, or instant-results promise needed for retention |
| Android | $25 one-time + build time | Waitlist demand; iOS retention proven |

General rule: **unlock a recurring cost when trailing 2-month gross profit covers it at least 3× over.** Unlock a one-time cost when trailing MRR repays it within 6 months.

## 6. Pricing guardrails (hypothesis; test in Phase 1)
- At ~$0.50/month video cost per active bowler, any subscription above a few dollars carries a healthy margin even after the App Store's cut (15% under the Small Business Program).
- The unoptimized pipeline (~$3–6/user) would wipe that out. **Don't launch paid analysis until cost per clip is measured and near target.**
- Tournament directors pay nothing at launch; bowlers acquired through tournaments are the return.

## 7. Risks
- **Free tier abuse:** someone uploads hundreds of clips. Mitigated by caps and the pre-upload capture check.
- **Slow async results hurt the "wow" moment.** Mitigate with a fast Stage A (pins, speed, boards) even when the rest is queued.
- **Supabase free tier pauses inactive projects.** Fine for development, risky once real users depend on it; move to Pro at beta if it pauses.
- **Legal can't be deferred.** Terms/privacy before beta and insurance/minors before tournaments are the non-negotiable early spend.

## 8. Proposed decision (for review)
**DEC-030 — Revenue-gated infrastructure (proposed).** Near-zero-cost features are free; cloud video analysis is metered (capped free tier, paid unlimited). Infrastructure and one-time costs unlock only when the triggers in `ROLLOUT_STRATEGY.md` §5 are met. Async scale-to-zero analysis is the default until paid demand justifies warm capacity or on-device analysis.
