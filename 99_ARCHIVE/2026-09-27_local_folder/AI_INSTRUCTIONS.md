# LaneSight AI Instructions
Before doing LaneSight product, design or engineering work:
1. Read `00_CONTEXT/LANESIGHT_MASTER_CONTEXT.md`.
2. Read `00_CONTEXT/CURRENT_STATE.md`.
3. Read `00_CONTEXT/DECISIONS.md`.
4. Read the relevant domain document.

Rules:
- Treat CANONICAL documents as source of truth.
- Do not resurrect superseded assumptions.
- Do not make LaneSight dependent on Meta glasses or one sensor vendor.
- Do not silently change accepted decisions; record a new decision or mark the old one superseded.
- When implementation materially changes the product, update CURRENT_STATE and the relevant domain file in the same change.
- Keep external integrations source-aware and do not assume unofficial APIs exist.
- Reference `01_PRODUCT/BUILD_PLAN.md` task IDs (e.g. P0-04) in work and commits; check a task off only when it's done and verified.
