# Instructions for AI assistants (Claude, ChatGPT, others)

This repo is the **source of truth** for LaneSight product and engineering context. Read these files first, in this order:

1. `00_CONTEXT/LANESIGHT_MASTER_CONTEXT.md`: what LaneSight is, strategy, terminology
2. `00_CONTEXT/CURRENT_STATE.md`: what is being built now, blockers
3. `00_CONTEXT/DECISIONS.md`: decision log (DEC-001…). Later decisions override earlier ones.
4. `01_PRODUCT/BUILD_PLAN.md`: staged task list with IDs and status
5. `01_PRODUCT/METRIC_CAPABILITIES.md` and `01_PRODUCT/FEATURE_REVIEW.md`: what each metric can promise and MVP vs MVP+
6. `02_RESEARCH/`: validation evidence and plans
7. `03_ENGINEERING/`: implementation specs

## Rules
- If documents conflict, `DECISIONS.md` and `CURRENT_STATE.md` win over older docs. Anything in `99_ARCHIVE/` is historical only.
- To change a decision, add a new DEC entry and mark the old one superseded. Never edit history.
- When you update a doc, bump its `Version` and `Last Updated` header.
- Google Drive copies of these files are read-only mirrors. Make edits here.
