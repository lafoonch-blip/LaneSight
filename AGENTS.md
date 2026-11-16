# Instructions for AI assistants (Claude, ChatGPT, others)

## Quick start: where the truth is (read before anything else)
**One central location: this repo.** Every change to context, decisions, designs (as synced files) and code lands here. Anything elsewhere is either an upstream editor that syncs into this repo, or a read-only mirror.

| Area | Source of truth | Not a source |
|---|---|---|
| Newest state of everything | Repo on Shayne's Mac, `~/Developer/LaneSight`, current working branch (often ahead of GitHub) | Your memory of an earlier chat |
| Pushed state | GitHub `lafoonch-blip/LaneSight` | — |
| Decisions | `00_CONTEXT/DECISIONS.md` (highest DEC number wins) | Older docs, `99_ARCHIVE/` |
| What's being built now | `00_CONTEXT/CURRENT_STATE.md`, `03_ENGINEERING/DEV_BUILD_PLAN.md` | — |
| App screen designs (DEC-091) | Figma "Target state – v3.7" + build queue `03_ENGINEERING/APP_DESIGN_CHANGES.md` (PNGs in `02_DESIGN/target_state/screens/`) | `02_DESIGN/dev_build_v0/` (frozen 2026-10-26), old mockups |
| Visual standards (color, type, spacing) | Figma "01 - Design Standards" page | Colors in old docs/UI Spec v1 |
| Logo and app/web icons | Figma Design Components › "Brand standards" → exported to `02_DESIGN/brand/` (DEC-054) | **The LS monogram concept: never use it** |
| Code | `lanesight-core/` (Python CV/API), `ios/LaneSight/` (SwiftUI) | — |
| Mirror (read-only, may lag) | claude.ai LaneSight Project docs | Never edit it as the source. The Google Drive copies are retired (frozen 2026-10-14, labeled STALE) |

### Freshness check (do this first, every session)
1. If you can reach the repo: `git fetch && git status && git branch --show-current && git log --oneline -5`. Work from the newest local branch, not an old clone or a pasted file.
2. Read the last ~5 entries of `DECISIONS.md` and the top of `CURRENT_STATE.md`.
3. Compare any doc you were handed (mirror, upload, paste) by its `Version` / `Last Updated` header against the repo copy. If the repo is newer, use the repo.
4. Before building UI: read `03_ENGINEERING/APP_DESIGN_CHANGES.md` (build every NOT BUILT entry) and `02_DESIGN/target_state/README.md` (changelog at the bottom).
5. Several AI sessions may work at once. Re-read a file right before you edit it; never overwrite changes you didn't read.

### When you change something
- Write it to this repo in the same session (doc, DEC entry, design sync or code). A change that lives only in a chat, canvas, Figma or a mirror is not done.
- Design changes (Figma): add an entry to `03_ENGINEERING/APP_DESIGN_CHANGES.md` with PNGs in `02_DESIGN/target_state/screens/<date>/` in the same session (DEC-091).
- Decisions: add a new DEC; mark the old one superseded. Docs: bump `Version` / `Last Updated`.
- Commit locally; push to GitHub only when Shayne says so. Then re-sync the claude.ai Project docs (don't update the retired Drive copies).
- Report what you changed and anything you could not update.
- Handoffs: to hand work to another session, copy `03_ENGINEERING/HANDOFF_TEMPLATE.md` to `03_ENGINEERING/HANDOFF_<YYYY-MM-DD>_<topic>.md` and fill in every placeholder — don't improvise the format. (Or run `/handoff`.) The template itself never changes.

This repo is the **source of truth** for LaneSight product and engineering context. Read these files first, in this order:

1. `00_CONTEXT/LANESIGHT_MASTER_CONTEXT.md`: what LaneSight is, strategy, terminology
2. `00_CONTEXT/CURRENT_STATE.md`: what is being built now, blockers
3. `00_CONTEXT/DECISIONS.md`: decision log (DEC-001…). Later decisions override earlier ones.
4. `01_PRODUCT/BUILD_PLAN.md`: staged task list with IDs and status
5. `01_PRODUCT/METRIC_CAPABILITIES.md` and `01_PRODUCT/FEATURE_REVIEW.md`: what each metric can promise and MVP vs MVP+
6. `01_PRODUCT/METRIC_AND_SCORING_LOGIC.md`: the current-state register of every metric & score formula (LaneSight Score, Performance, Accuracy, Consistency, Power, and the video metrics), each pointing to its governing DEC. Maintain it in lockstep with `DECISIONS.md`
7. `02_RESEARCH/`: validation evidence and plans
8. `03_ENGINEERING/`: implementation specs

## Rules
- If documents conflict, `DECISIONS.md` and `CURRENT_STATE.md` win over older docs. Anything in `99_ARCHIVE/` is historical only.
- To change a decision, add a new DEC entry and mark the old one superseded. Never edit history.
- When you update a doc, bump its `Version` and `Last Updated` header.
- The claude.ai LaneSight Project holds a read-only mirror of these files (DEC-025). Make edits here, then re-sync it. The Google Drive copies were retired on 2026-10-25.
