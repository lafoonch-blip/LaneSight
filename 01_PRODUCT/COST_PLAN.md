# LaneSight Cost Plan (target state, excluding coaching)
Status: DRAFT (for Shayne's review)
Version: 1.0
Last Updated: 2026-10-15
Owner: Shayne
Scope: every MVP feature (DEC-019) plus sensors, tournament management (proposed DEC-026) and later league/center features. **Excluded:** coaching features (Execution/Lane Coach, Audio Coach + TTS, coach review M4-08, coach share/coaching tier).
Prices: checked 2026-10-15 where marked ✓; others are estimates (≈) to confirm before budgeting.

---

## 1. Bottom line
- **One cost dominates: cloud video analysis.** Everything else (database, web hosting, email, app store) is small at any realistic scale.
- At target efficiency, an actively filming bowler costs about **$0.50–0.60/month**. If the pipeline stays near today's speed (minutes per clip), that rises to **$3–6/month**, which would break a low-priced subscription.
- Three choices control the bill: **(1) GPU seconds per clip** (or on-device analysis), **(2) raw-video retention**, **(3) where video lives** (zero-egress object storage, not Supabase Storage).
- Tournament-only users cost almost nothing (a database row, a few emails, push).
- Fixed overhead before scale: about **$150–250/month** in services, plus **$10–30k one-time** for legal, insurance and validation.

## 2. Unit assumptions (change these first)

| Assumption | Value | Why |
|---|---|---|
| Clips per active filming bowler / month | 100 typical, 240 heavy | ~40 balls/session × 2.5 sessions typical; 6 sessions heavy |
| Clip size (1080p60 HEVC, ~8 s) | ~15 MB | ≈; measure from real AirDrop clips |
| GPU time per clip, target | 15 s (L4) | Needed for the ≤10 s cloud latency target (C-03) |
| GPU time per clip, unoptimized | 120 s | Today's pipeline is "a few minutes" on CPU |
| Raw video retention default | 30 days, then derived data only | Proposed; trajectory, metrics, replay image stay forever |
| Share of MAU who film | 60% | The rest use stats/tournaments/manual entry |

## 3. Variable costs per active filming bowler / month

| Item | Rate | Typical (100 clips) | Heavy (240) | Notes |
|---|---|---|---|---|
| GPU analysis, target 15 s/clip | L4 on Modal $0.000222/s ✓ ($0.80/hr) | $0.33 | $0.80 | Cheaper L4 hosts exist (~$0.39/hr ✓) with more ops work |
| CPU/memory overhead (decode, upload handling) | ≈ | $0.10 | $0.25 | |
| **GPU if unoptimized (120 s/clip)** | same | **$2.66** | **$6.39** | The risk case |
| Raw video storage, 30-day retention | R2 $0.015/GB-mo ✓ | $0.02 | $0.05 | ~1.5 GB rolling |
| Raw video storage, keep forever (month 12) | same | $0.27 and rising | $0.65 and rising | 18 GB/user after a year |
| Video egress (replays, downloads) | R2 egress free ✓ | $0 | $0 | Supabase Storage egress is $0.09/GB over the included 250 GB ✓; keep video off it |
| Replay video renders (share cards) | GPU/CPU ≈ | $0.02 | $0.05 | Render on demand, cache |
| **Total, target** | | **≈$0.50** | **≈$1.15** | |

Non-filming users (stats, manual entry, tournament participants): **< $0.01/month** each.

## 4. Platform services (monthly)

| Service | 1k MAU | 10k MAU | 50k MAU | Notes |
|---|---|---|---|---|
| Supabase (Postgres, Auth, Realtime) | $25–40 | $60–150 | $300–700 | Pro $25 incl. $10 compute credit, 100k MAU, 8 GB DB ✓. Compute tier is the growth driver |
| Supabase Team plan (if SOC 2 / SSO needed for centers) | — | — | $599 ✓ | Only for B2B center/league deals |
| Web hosting (director console, registration, marketing) | $20 | $20–60 | $60–200 | Vercel Pro ≈$20/seat |
| Transactional email (confirmations, claim links, results) | $0–20 | $20–35 | $50–100 | ≈ Postmark/Resend tiers |
| Push notifications (APNs) | $0 | $0 | $0 | Free from Apple |
| Error/perf monitoring | $0–26 | $26–80 | $80–200 | ≈ Sentry |
| Logging / job queue / misc | $10 | $30 | $100 | |
| Center lookup (if using a places API) | $0–20 | $20–50 | $50–150 | ≈; a curated list avoids it |
| **Subtotal** | **$55–135** | **$175–405** | **$640–1,450** (+$599 if Team) | |

## 5. Total monthly run-rate (target efficiency)

| | 1k MAU | 10k MAU | 50k MAU |
|---|---|---|---|
| Filming bowlers (60%) | 600 | 6,000 | 30,000 |
| Video analysis + storage | ~$300 | ~$3,000 | ~$15,000 |
| Platform services | ~$100 | ~$300 | ~$1,000 |
| **Total** | **~$400/mo** | **~$3,300/mo** | **~$16,000/mo** |
| **If pipeline unoptimized** | ~$1,800/mo | ~$17,000/mo | ~$85,000/mo |

## 6. Revenue-side costs (not run-rate, but plan for them)

| Item | Rate | Notes |
|---|---|---|
| App Store commission on subscriptions | 15% under Apple's Small Business Program (<$1M/yr), 30% otherwise ≈ | Largest cost on paid users once subscriptions launch |
| Apple Developer Program | $99/yr | Google Play $25 one-time if Android |
| Card processing (tournament entries, if online) | 2.9% + $0.30 per charge ✓ | |
| Stripe Connect, "Stripe handles pricing" | No platform fees ✓ | Director's account pays processing. Recommended under proposed DEC-027 |
| Stripe Connect, "you handle pricing" | $2 per active account/mo + 0.25% + $0.25 per payout ✓ | Only if LaneSight sets fees and earns margin |

## 7. One-time and annual costs

| Item | Estimate | When | Notes |
|---|---|---|---|
| **Validation (Stage 1 gate)** | | Now | |
| Witsee sensor | TBD | Now | Price + export capability to confirm (R-02) |
| F5 sensor + drilling/insert | TBD | Now | In-ball sensors need a ball drilled or insert installed |
| Lane time for Seed Dataset (30–50 shots × several sessions) | $200–600 ≈ | Now | |
| Specto sessions | $100–500 ≈ | Now | Depends on the center; data access unconfirmed |
| Tripods, phone mounts, second phone for capture-tier matrix | $100–400 ≈ | Now | |
| Meta glasses for moving-camera eval | $300–800 ≈ | Stage 2 | |
| GPU for detector benchmarking/training | $100–500 ≈ | Stage 1–2 | |
| **Legal and business** | | Before beta | |
| LLC formation + registered agent (VA) | $100–300/yr ≈ | | |
| Terms, Privacy Policy, video retention language | $1,500–5,000 ≈ | Before beta | Templates + lawyer review |
| COPPA / minors policy review | $1,000–3,000 ≈ | Before tournaments | Youth bowlers in tournaments |
| Payments / bracket & side-pot legality review (VA) | $2,000–5,000 ≈ | Before online payments | Proposed DEC-027 |
| General liability + cyber / tech E&O insurance | $1,500–4,000/yr ≈ | Before tournament pilots | Directors may ask for it |
| **Data** | | | |
| Ball catalog (curated from manufacturer specs) | Your time; licensing TBD | MVP | Check manufacturer terms |
| Oil pattern library | Your time; licensing TBD | MVP | Check terms of any published library |
| Pro-shop review of layout presets | $200–500 ≈ | MVP | Arsenal, not coaching |
| **Security / quality** | | | |
| Penetration test | $4,000–15,000 ≈ | Before online payments or center B2B | |
| Accessibility review | $1,000–3,000 ≈ | Before public launch | Tournament PRD launch gate |
| **Tournament pilots** | | | |
| Desk tablet + printer supplies for pilots | $300–600 ≈ | Pilot | Lend to directors |

Rough one-time total before public launch: **$10,000–30,000**, most of it legal, insurance and a pen test. Validation hardware is the near-term spend.

## 8. Biggest levers

| Lever | Effect | Decision |
|---|---|---|
| On-device analysis for Stage A metrics (Core ML on iPhone) | Cuts cloud GPU cost toward $0 and helps the ≤5 s edge target | Make it part of the C-03 on-device vs cloud DEC |
| Pipeline optimization (Milestone 4) | 120 s → 15 s GPU per clip is the difference between ~$3 and ~$0.50 per user | Treat cost-per-clip as a Stage 8 gate metric |
| Raw video retention = 30 days | Keeps storage flat instead of growing forever | Add to the privacy/retention decision (Master Context open question) |
| Video in R2 (zero egress), not Supabase Storage | Removes the only cost that scales with sharing | Engineering default |
| Free-tier clip cap | Bounds cost of non-paying users | Ties to the open pricing question |
| Stripe "handles pricing" for tournaments | No platform payment fees or payout liability | Proposed DEC-027 |

## 9. Gaps in this estimate
- No staff costs (support, contractors, marketing). Weekend tournament support is the first likely need.
- GPU seconds per clip is a guess until the pipeline runs on a GPU. Measure it once and update §2.
- Sensor prices, Specto access and licensing for ball/oil data are unknown.
- No Android, Team Lane Management, or League Mode continuous capture (rolling buffer would multiply processed video several times).

Sources: Supabase pricing (makerkit.dev, cloudzero.com, toolradar.com, Sept–Oct 2026 summaries); Modal L4 rate (modal.com blog, usagepricing.com); L4 market rates (computeprices.com); Cloudflare R2 (spendbase.co); Stripe Connect (stripe.com/connect/pricing).
