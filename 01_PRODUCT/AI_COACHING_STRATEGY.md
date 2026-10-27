# LaneSight — AI Coaching Strategy
Status: PROPOSED STRATEGY (not an accepted DEC or MVP scope change)  
Version: 1.0  
Last Updated: 2026-10-27  
Owner: Shayne  
Branch context: based on pushed `dev-build-v0` as of 2026-10-27; the Mac working tree may be newer.

## 1. Strategic thesis
LaneSight's defensible advantage should become **measured improvement**, not a generic bowling chatbot. Video, optional sensors, scores, form, arsenal and session history supply evidence; structured coaching interventions, human-expert corrections and longitudinal outcomes turn evidence into personalized guidance. Stronger defensibility is a hypothesis to validate with coaching efficacy and retention data, not a guaranteed moat.

**North-star loop:** Measure → Diagnose → Recommend → Practice → Re-measure → Learn → Adapt. 
Do not claim an intervention caused improvement without an appropriately designed evaluation; say 'associated with' when warranted.

## 2. Alignment with accepted decisions
- DEC-005: Preserve separate **Execution Coach** and **Lane Coach** evidence paths. Execution misses are not lane-transition evidence (DEC-006).
- DEC-002/021: Sensor enhancements optional; retain source and independent comparability of metrics.
- DEC-003/007/009: Bowler Profile persistent; actual ball configuration, surface and imported-data provenance are first class.
- DEC-038/041: Keep **one** LaneSight Score; do not add an Improvement Score or a form-score pillar. Coaching progress is separate from the score.
- DEC-047: MVP (founder only) → friends Beta → market. Stage gates are evidence; MVP exit remains Shayne's judgment. This document does not broaden current MVP scope.
- DEC-061/065: Never infer from unavailable or low-confidence metrics. In particular, **far-lane measures remain unavailable** until Phase-2 camera validation and real-ball accuracy checks are satisfied. No fabricated entry angles/boards, breakpoint or late speed.
- DEC-014/015: Non-user video is discarded promptly; identity recognition remains session-scoped.
- Existing recommendation state machine and no-more-than-2-and-1 single-shot movement guidance remain controlling; coaching recommendations must respect the same guardrails.
- Any formal change to accepted scope, model behavior, data retention, or product decisions requires a **new decision entry** under `00_CONTEXT/DECISIONS.md`. This document does not edit decision history.

## 3. Core product pillars
1. **Measure** — trustworthy shot, ball, form, lane and scoring measurements, each with provenance and confidence.
2. **Understand** — personalized patterns and competing explanations, including execution versus lane reaction.
3. **Improve** — evidence-backed prescriptions, practice plans, outcome evaluation and human-coach collaboration.

## 4. Coaching capabilities and orchestration
| Module | Input evidence | Output | Delivery horizon |
|---|---|---|---|
| Execution Coach | Intent, near-lane path, pose/form metrics when validated, shot variance | Repeatability and technique hypotheses | existing engine → Beta enrichment |
| Lane Coach | Comparably executed shots, reliable lane/pin observations | No move or bounded lane/ball adjustments | existing engine → later enrichment |
| Practice Coach | Priorities, baselines, interventions, adherence and follow-up | Drills, measurable plans | Beta proposal |
| Spare Coach | Verified leaves, attempts, conversion trends | Spare practice and targeting | later enrichment |
| Equipment Coach | UserBall, surface/layout history, observed reaction | Compare equipment options | later; expert validation required |
| Competition Coach | Consent-eligible prior sessions and goals | Preparation and post-event reflection | later; verify competition rules |

Implement initially as **one orchestration service with specialized, testable modules**, not separate trained foundation models. Rule-based eligibility and ranking drive the recommendation; an LLM may explain and converse but **must not invent metric values or override guardrails**. The orchestration layer resolves conflicting recommendations and limits simultaneous coaching priorities.

## 5. Closed-loop experience
1. **Observe:** identify a repeatable deviation versus a personalized, context-aware baseline.
2. **Diagnose:** present an evidence-linked hypothesis with confidence, alternate explanations and missing-data caveats.
3. **Recommend:** one actionable change or practice drill with a measurable target; allow 'not enough evidence'.
4. **Attempt:** explicitly record whether and how the bowler tried the intervention (not presumed adherence).
5. **Re-measure:** compare comparable sessions with confidence intervals where feasible; account for ball/surface, pattern, session duration and fatigue.
6. **Evaluate:** label improved / neutral / worsened / insufficient evidence; do not mistake correlation for causation.
7. **Adapt and remember:** update individual learning history, keep unsuccessful suggestions and preserve audit history.

Example (illustrative only): 'Pushaway timing variability fell from 120 ms to 85 ms over comparable drills.' Such numbers can be shown **only if real validated pose/timing measurements are available**.

## 6. Coach integration: product and data flywheel
Position AI as an assistant to verified human coaches, not a replacement. With explicit student permission coaches can:
- Review selected shots, evidence and confidence states; annotate timestamped clips.
- Set custom student baselines, goals and drills **without overwriting LaneSight default benchmarks**.
- Approve, modify or reject a recommendation; enter differential diagnoses with structured reason codes.
- Assign plans and view adherence/outcome trends across sessions.
- Request AI summaries and retain human ownership of their recommendations.

**Human-feedback label schema:** `coach_id`, `student_id`, `shot/session`, `measurement_version`, `AI_recommendation_version`, `expert_diagnosis`, `correction_type`, `reason_codes`, `free_text`, `suggested_intervention`, `consent_scope`, `review_status`, `outcome_link`, timestamps.

Keep coach feedback distinguishable from validated ground truth. Calibrate reviewer reliability and resolve disagreements before including samples in evaluations or training. Establish contracts on coaching content, ownership, permission, commercial reuse, revocation and retention before training models on contributed materials.

## 7. Proposed data model (additive; not a migration approval)
- `CoachingObservation`: user, shot/session, issue taxonomy, measurements with sources/confidence, context, supporting/contradicting evidence, rule/model version.
- `CoachingRecommendation`: observation refs, chosen action, alternates, priority, rationale, abstention/eligibility decision, guardrail verdict, version.
- `CoachingIntervention`: recommendation, drill or adjustment, target, who prescribed, start/end, stated adherence and events.
- `CoachingOutcome`: intervention, comparable baseline/follow-up windows, metrics, uncertainty, confounders, result and evaluator version.
- `ExpertCoachingFeedback`: coach/student identities, permissions, annotation, rating/correction, taxonomy, review status and reuse eligibility.
- `BowlerDevelopmentProfile`: goals, strengths, working hypotheses, learning preferences, prioritized focus, history and permission boundaries.

Reuse existing `Observation`, `Recommendation`, `RecommendationOutcome` and `Measurement` where possible. Avoid creating parallel canonical objects: review actual schema before implementing. Preserve immutable recommendation snapshots and both original and amended interpretations. Every read should enforce row-level security, coach authorization and consent.

## 8. Knowledge, models and quality
Start with a curated and licensed bowling knowledge base (technique, drill library, equipment guidance, caveats), retrieval, typed tools and deterministic guardrails. Label sources and revision dates. Never scrape or train on copyrighted coaching videos without rights. Delay fine-tuning until labeled data, baseline performance and measurable lift justify cost.

Evaluation program:
- **Trust:** percent of recommendations correctly abstaining on unavailable/low-confidence measurements; unsupported assertion and policy breach rates.
- **Diagnostic quality:** inter-coach agreement, expert accept/edit/reject distributions; review disagreement rather than treating majority as truth.
- **User value:** recommendation follow-through, perceived helpfulness, repeat practice, retained users.
- **Outcomes:** direction and size of *comparable* pre/post changes, persistence, confounder coverage; controlled trials where feasible.
- **Operations:** inference cost per coached session, latency, cache hit rate, model drift, feedback/consent audit coverage.

Use locked datasets split by bowler/session/center and time to reduce leakage; track model, prompt, rules and CV versions. Shadow-test changed coaching logic before enabling to users.

## 9. Phased delivery without MVP scope inflation
| Workstream | Founder MVP | Friends Beta (proposal) | Later |
|---|---|---|---|
| Foundation | Preserve observation/recommendation provenance and abstention; define taxonomy and event schemas | Persist consented feedback/outcomes | Rich memory and model personalization |
| Advice | Existing guarded shot-level insight; honest partial analysis | Optional session summaries and 1–2 prioritized practice focus areas | Conversational contextual coaching |
| Practice | Instrumentation design only unless explicitly approved | Drill plan, adherence and comparable follow-up trial | Adaptive closed-loop coaching |
| Real coaches | Partnership interviews/requirements | Small permissioned expert review pilot if ready | Coach portal, custom benchmarks, multi-student plans |
| Learning | Rule and knowledge-base validation | Expert agreement studies, outcome evaluation | Fine-tuning only upon measured lift |

The Beta cohort size, timing and gates remain proposals, not binding rollout decisions. Production features require separate approved scope and privacy/security reviews.

## 10. UX integration
- **Home:** development priority and next practice prompt when evidence exists.
- **Performance Lab:** explain shot-versus-form analysis separately; link every insight to measurable evidence and capture limitations.
- **Session Review:** prioritized recap and opportunity to correct intent, pin results and perceived usefulness.
- **Stats:** patterns and score trends, per-ball comparisons; form diagnostics remain separate from the LaneSight Score.
- **Profile:** goals, feedback and coaching history.
- **Future Coach Portal:** per-student permissions, annotations, assignments and outcome reviews.

User-facing language: distinguish 'measured', 'inferred', 'coach opinion' and 'not available'. Explain recommendations in concise bowling terms. Show no invented numeric confidence if calibration is unvalidated.

## 11. Privacy, rights and safety
Record opt-in separately for (a) sharing with a named coach, (b) storing coaching annotations, and (c) using content to evaluate/improve shared models. No training use by default; withdrawal stops future training use and should have documented effects on previously trained models. Apply retention/deletion policies to video and derivatives. Protect minors under the current age policy. Never use bystander footage as training evidence. Competition/live audio advice may be prohibited; verify rules before promoting.

## 12. Business model hypotheses
Free: measured basics and limited insights. Pro: personalized trends and practice. Coach: student workflow and custom benchmarks. Elite/coach+AI: optional advanced individualized guidance. These are hypotheses, **not approved pricing or entitlements**. Validate willingness to pay and coach economics.

## 13. Recommended near-term actions
1. Audit current insight and database schema; map new events to existing entities.
2. Write the coaching taxonomy and metric-eligibility contract (including DEC-065).
3. Capture recommendation versions, explicit bowler feedback, intervention attempts and subsequent outcomes without changing MVP UI.
4. Assemble coach-reviewed, appropriately licensed knowledge and drill candidates.
5. Build a locked coaching evaluation set and abstention tests.
6. Recruit a small advisory group of coaches; document permission and content rights.
7. Pilot one controlled closed-loop practice workflow before expanding model complexity.

## 14. Open decisions for Shayne
- Approve coaching as an explicit long-term differentiation pillar and ownership of the Coaching Intelligence Program.
- Approve data-capture additions and consent policy before engineering migrations.
- Select first coach partnership workflow and compensation model.
- Choose Beta coaching features based on actual measurement reliability and founder MVP evidence.
- Confirm licensing/training-use terms with legal counsel before collecting expert data for model development.

Related: `00_CONTEXT/LANESIGHT_MASTER_CONTEXT.md`, `00_CONTEXT/CURRENT_STATE.md`, `00_CONTEXT/DECISIONS.md`, `01_PRODUCT/BUILD_PLAN.md`, `01_PRODUCT/METRIC_CAPABILITIES.md`, `01_PRODUCT/FEATURE_REVIEW.md`.
