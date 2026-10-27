# LaneSight Legal, Entity & IP Launch Strategy
Status: PROPOSED / ACTION PLAN (not a legal opinion)
Version: 1.0
Last Updated: 2026-10-26
Owner: Shayne
Scope: controlled beta → paid launch → scalable partnerships
Authority: Operational planning context only. `00_CONTEXT/DECISIONS.md` and `00_CONTEXT/CURRENT_STATE.md` govern if conflicts arise.

## 1. Objective and principles
Establish an independently owned, legally compliant LaneSight business before broader testing or commercialization; preserve brand and potentially patentable inventions; secure user video/data and partner rights; manage spending in stages. A recommended action is **not** an accepted DEC or proof an action was completed. Legal conclusions and filings require attorney/agency verification.

**Immediate gates:** (1) trademark clearance before a major public brand commitment; (2) entity formation, founder IP chain-of-title, and account ownership; (3) beta terms/privacy/consent; (4) patentability and disclosure review before publishing technical inventions.

## 2. Entity, EIN and financial separation
**Proposed default:** Virginia single-member LLC, subject to available entity name and review of tax/employer constraints; separate LaneSight from LandForge and TimberForge. If venture financing or equity issuance is near-term, discuss Delaware C-corp now rather than automatically choosing an LLC.

- Check Virginia SCC entity-name availability; file articles; select a compliant registered agent; establish operating agreement and ownership records.
- Obtain EIN directly from IRS (free); set up business checking, expense ledger, accounting and annual compliance calendar.
- Determine relevant Virginia/local business registration, taxes, and other-state sales-tax/economic nexus obligations before revenue.
- Review employment invention-assignment, moonlighting/conflicts and resource-use policies; document independent development without employer resources.
- Transfer/assign pre-formation IP and assets to company: source and repositories, algorithms, logos/Figma, domains, contracts, app-store rights, datasets and design work. Obtain contributor/contractor work-made-for-hire **and present assignment** provisions as applicable, plus confidentiality.
- Confirm company administrative control of GitHub, Supabase, Google Cloud, Apple Developer, Google Play, Figma, domain/DNS, billing, and recovery; use MFA and least privilege.
- **Planning costs:** VA LLC filing ~$100, annual fee ~$50, EIN $0; legal/accounting/agent costs vary. Verify current government fee schedules at filing.

**Deliverables:** formation confirmation, EIN letter, operating agreement, founder/contractor IP assignments, business account, compliance calendar, service ownership inventory.

## 3. Trademark/brand clearance and registration
**Proposed filing order:** LaneSight word mark first, final logo second, future marks (e.g., LaneSight Score) only if commercially warranted. Candidate classes: 9 (downloadable software), 42 (hosted software), potentially 41 (education/coaching); counsel to define actual goods/services and application basis.

**Clearance workflow:**
1. Search USPTO federal records for exact/similar marks and related goods, plus state records, common-law commercial use, app stores, domains and social handles.
2. Investigate the previously noted Florida business entity named *LaneSight, Inc.*: **existence/status and possible relevance have not been independently verified in this document**. An entity-name match is neither proof of trademark conflict nor clearance.
3. Have trademark counsel assess likelihood of confusion, available filings and whether a brand change or coexistence is sensible.
4. Consider intent-to-use filing before commercial availability; track proof of use and subsequent deadlines. Do not claim federal registration merely upon filing.
5. Preserve evidence of first use, artwork authorship, branding and marketing approval.

**Budget planning:** USPTO base trademark application fee ~$350/class (verify), plus optional counsel/clearance and later filing fees. Allow ~$1,000–$2,500 initial trademark work depending on classes and review. **Gate:** no major paid marketing, packaging, or partner brand commitments before satisfactory clearance.

## 4. Patent and trade-secret strategy
Patentability is **unassessed**. Avoid assuming a broad AI coaching concept or scoring formula is patentable. Prioritize actual novel *technical* solutions with demonstrable improvements. Candidate invention families:
- Robust video calibration/geometry recovery across bowling lanes and camera positions;
- Video motion/object detection, event localization and measurement under occlusion, frame-rate and lighting limitations;
- Multi-source sensor/video/scoring timing alignment, confidence and validation;
- Novel technical performance-measurement methods (vs broad recommendations or generic analytics).

**Procedure:**
1. Inventory implemented inventions from `lanesight-core/`, engineering specs, commit history and experiments, with inventors, dates, novelty claims, quantitative evidence and known third-party work.
2. Search USPTO/Google Patents and literature, including related sports vision and bowling vendors; separately consider freedom-to-operate risks.
3. Review strongest 1–2 candidates with U.S. patent counsel. Keep enabling technical details confidential pending a disclosure strategy.
4. If justified, file technically detailed provisional application **before public technical disclosure**; calendar the 12-month nonprovisional deadline and decide on international strategy early. A provisional is not examined or an enforceable patent.
5. Protect nonpatented implementations with trade-secret access controls, confidentiality obligations and limited disclosure.

**Estimated spend:** early research $0–$500 DIY; counsel assessment ~$1k–$3k; provisional attorney draft ~$2.5k–$6k+ plus agency fees; nonprovisional much higher. Amounts illustrative only.

## 5. Domains, identity and accounts
- Confirm actual ownership/renewal/control of existing `lanesight.tech`; verify availability/price of `lanesight.com`, `lanesight.app`, and optional defensive names. **No availability or ownership check documented here.**
- Prefer one canonical site/domain with redirects. Do not overpay for premium domains before commercial validation.
- Configure business email aliases: hello@, support@, partnerships@, coaches@, legal@; set SPF/DKIM/DMARC; enable auto-renew, registrar lock and MFA.
- Ensure entity-managed Apple/Google publisher identities and platform policies before submitting apps.

## 6. Beta privacy, user contracts and data governance
**Mandatory prior to external beta:**
- Attorney-reviewed terms, privacy notice, beta terms and product claims/disclaimer; process to accept/version consent.
- Recording policy covering bystanders, bowling-center rules, recording permissions, and no unauthorized footage distribution. Separate private analysis from publication/sharing permissions.
- Clearly disclose types of video, body/pose/movement, sensor, score, account and device data; processing purposes, processors, retention, transfer and deletion rules.
- Implement rights/requests workflows (access, deletion, account deletion), retention minimization, encryption, logs, incident response and processor DPAs where appropriate.
- Do not use user clips for model training by default without a clear, appropriate disclosure and consent/legal basis.
- Limit initial beta to adults; specifically review COPPA, youth participation and biometric/privacy statutes before expanding.
- Avoid persistent biometric identification by default; align with DEC-014 session-scoped recognition and prompt disposal of other bowlers' footage.
- Align in-app deletion, subscriptions, reporting and privacy disclosures with Apple/Google policies.

**Acceptance evidence:** published terms/privacy, consent logs, retention schedule, deletion test, subprocessors inventory, breach response runbook, staff/admin access controls.

## 7. Partner and content rights
Prior to shipping third-party features, document permitted uses, access, branding, termination, redistribution, privacy and data ownership.
- QubicaAMF/Bowlero/bowling centers: authorized access to scoring/pinfall/league data, venue recording restrictions and commercial-use rights.
- Hardware/sensor makers: APIs, SDK licenses, branding, telemetry rights and distribution constraints.
- Coaches: service/fee and consumer relationships, benchmark ownership, data access, liability and termination.
- PBA/professional comparisons: legitimate rights to footage, likeness/endorsements and licensed data; keep disabled until resolved.
- Open-source/AI: run license/SBOM audit; verify video models, libraries, datasets, stock images, ball catalog photos and AI service terms permit the planned commercial use.

## 8. Insurance, payments and compliance
- Explore technology E&O and cyber insurance before broad paid launch; general liability as warranted, D&O later if needed.
- Evaluate entity taxes and SaaS sales-tax nexus; Stripe/App Store/Play billing, cancellation, refunds, chargebacks, and subscription disclosures.
- Review advertising claims, testimonials, accuracy representations and data provenance; avoid guaranteeing ball metrics that have not been validated.
- Verify current FinCEN BOI status when forming; U.S.-created entities were exempt under 2025 interim rule, but requirements can change.

## 9. 30-day workplan and owners
| When | Task | Priority | Owner | Evidence/Gate |
| --- | --- | --- | --- | --- |
| Week 1 | Trademark preliminary search + legal counsel | P0 | Founder + trademark counsel | Clearance memo |
| Week 1 | Entity choice, Virginia filing, EIN, bank | P0 | Founder + CPA/counsel | LLC/EIN/bank records |
| Week 1 | Employment/IP conflicts and asset/account inventory | P0 | Founder + counsel | Signed assignment plan, ownership register |
| Week 2 | Beta legal terms, privacy/recording consent and rights flows | P0 | Founder + privacy counsel/engineering | Approved docs and implementation tests |
| Week 2 | Technical invention inventory and prior-art scan | P1 | Engineering + patent counsel | Ranked invention disclosures |
| Week 3 | File trademark application **only if cleared** | P1 | Trademark counsel | Filing receipt + deadlines |
| Week 3 | Validate retention/deletion, model-training opt-in and bystander policy | P0 | Engineering/product | QA evidence |
| Week 4 | File provisional **only if warranted**, before material public disclosure | P1 | Patent counsel | Application receipt/deadline calendar |
| Week 4 | Partner licensing templates; payment/insurance review | P1 | Founder + counsel/CPA | Executable templates and launch decision |
| Before external beta | Legal launch-readiness review | **GATE** | Founder | Written go/no-go sign-off |

## 10. Stage-gated budget
- **Lean:** roughly $1.5k–$3.6k for formation, basic counsel/terms, clearance/filing, domains and initial patent screening.
- **IP-focused:** roughly $6.25k–$14.65k including deeper counsel, provisional filing and some insurance.
- **Recommended initial envelope:** $3k–$5k, then fund patent prosecution only on a credible invention assessment. These are nonbinding planning estimates, not quotes.

## 11. Open decisions and tracking
| Item | Status | Dependency |
| --- | --- | --- |
| Virginia LLC vs Delaware corporation | Proposed | Financing/tax/legal review |
| LaneSight brand clearance | Not done | Federal/state/common-law review |
| Patentability of measurement technology | Not done | Actual implementation + counsel review |
| Domain acquisitions | Not verified | Registrar availability/price |
| Ownership assignments, employer review | Not done | Counsel and contributor inventory |
| Beta policy/consent/deletion readiness | Not done | Product + legal validation |
| Third-party scoring and PBA rights | Not done | Written licenses |
| Insurance/carrier choice | Not done | Quotes and risk assessment |

## 12. Official reference starting points
- Virginia SCC LLC forms/fees: https://www.scc.virginia.gov/businesses/forms-and-fees/virginia-limited-liability-companies/
- IRS EIN: https://www.irs.gov/businesses/small-businesses-self-employed/get-an-employer-identification-number
- USPTO clearance: https://www.uspto.gov/trademarks/search
- USPTO trademark fee schedule: https://www.uspto.gov/trademarks/trademark-fee-information
- USPTO provisional applications: https://www.uspto.gov/patents/basics/apply/provisional-application
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- FTC COPPA guidance: https://www.ftc.gov/business-guidance/privacy-security/childrens-privacy
- FinCEN BOI: https://www.fincen.gov/boi

> Legal and patent guidance is preliminary. Reverify agency fees, requirements, trademark conflicts and eligibility at execution. No filing or clearance is represented as completed.
