# Instructions for AI assistants (Claude, ChatGPT, others)

## Quick start: where the truth is (read before anything else)
**One central location: this repo.** Every change to context, decisions, designs (as synced files) and code lands here. Anything elsewhere is either an upstream editor that syncs into this repo, or a read-only mirror.

| Area | Source of truth | Not a source |
|---|---|---|
| **Live status — what every session is doing right now** | **`STATUS.md` on the `context` branch** (single source of truth; read it first, every session — see below) | A code branch's docs; your memory of an earlier chat |
| Open cross-session requests/decisions | `INBOX.md` on the `context` branch | — |
| Newest state of everything | Repo on Shayne's Mac, `~/Developer/LaneSight`, current working branch (often ahead of GitHub) | Your memory of an earlier chat |
| Pushed state | GitHub `lafoonch-blip/LaneSight` | — |
| Decisions | `00_CONTEXT/DECISIONS.md` (highest DEC number wins) | Older docs, `99_ARCHIVE/` |
| Architecture + history of what was built | `00_CONTEXT/CURRENT_STATE.md` (a durable architecture/decision record and running history — **not** the live task board; for "who is doing what now", read `STATUS.md` on `context`) | Treating it as the live status board |
| Metric honesty contract (status / evidence / display / coaching eligibility) | `01_PRODUCT/METRIC_CAPABILITIES.md` | Any doc that still says "Guaranteed" |
| App screen designs (DEC-091) | Figma "Target state – v3.7" + build queue `03_ENGINEERING/APP_DESIGN_CHANGES.md` (PNGs in `02_DESIGN/target_state/screens/`) | `02_DESIGN/dev_build_v0/` (frozen 2026-10-26), old mockups |
| Visual standards (color, type, spacing) | Figma "01 - Design Standards" page | Colors in old docs/UI Spec v1 |
| Logo and app/web icons | Figma Design Components › "Brand standards" → exported to `02_DESIGN/brand/` (DEC-054) | **The LS monogram concept: never use it** |
| Code | `lanesight-core/` (Python CV/API), `ios/LaneSight/` (SwiftUI) | — |
| Mirror (read-only, may lag) | claude.ai LaneSight Project docs | Never edit it as the source. The Google Drive copies are retired (frozen 2026-10-14, labeled STALE) |

### Freshness check (do this first, every session)
1. **Live status lives on the `context` branch, not on any code branch.** At session start: `git -C ~/Developer/LaneSight fetch -q origin context`, then read `git show origin/context:STATUS.md` and `…:INBOX.md` (and any `…:handoffs/<file>` an INBOX item points to). `STATUS.md` is the single source of truth for what each session is doing now; act on every OPEN INBOX item addressed to you and mark it DONE with your commit hash. To edit these, use the worktree `~/Developer/LaneSight-context` (create once: `git -C ~/Developer/LaneSight worktree add ../LaneSight-context context`), `git pull`, edit only your own rows/sections, `git commit --no-verify`, push, and verify `git ls-remote origin context`. **Never put code on `context`; never merge `context` into a code branch or vice versa.**
2. If you can reach the repo: `git fetch && git status && git branch --show-current && git log --oneline -5`. Work from the newest local branch, not an old clone or a pasted file.
3. Read the last ~5 entries of `DECISIONS.md`. `CURRENT_STATE.md` is the architecture/history record, not the live task board (that's `STATUS.md` on `context`).
4. Compare any doc you were handed (mirror, upload, paste) by its `Version` / `Last Updated` header against the repo copy. If the repo is newer, use the repo.
5. Before building UI: read `03_ENGINEERING/APP_DESIGN_CHANGES.md` (build every NOT BUILT entry) and `02_DESIGN/target_state/README.md` (changelog at the bottom).
6. Several AI sessions may work at once. Re-read a file right before you edit it; never overwrite changes you didn't read.

### When you change something
- Write it to this repo in the same session (doc, DEC entry, design sync or code). A change that lives only in a chat, canvas, Figma or a mirror is not done.
- Design changes (Figma): add an entry to `03_ENGINEERING/APP_DESIGN_CHANGES.md` with PNGs in `02_DESIGN/target_state/screens/<date>/` in the same session (DEC-091).
- Decisions: add a new DEC; mark the old one superseded. Docs: bump `Version` / `Last Updated`.
- **Push rule (one rule, everywhere):** push **your own branch** once tests + the applicable gates pass, then verify with `git ls-remote origin <branch>`. **Never push or merge to `main`.** **Only Session 1 (the single deployer) deploys to Cloud Run**, and never an unpushed commit. Branch-specific exceptions (e.g. a feature branch that still waits on Shayne) are noted in `STATUS.md` on `context`. After a push, re-sync the claude.ai Project docs (don't update the retired Drive copies).
- Report what you changed and anything you could not update.
- Handoffs: to hand work to another session, copy `03_ENGINEERING/HANDOFF_TEMPLATE.md` to `03_ENGINEERING/HANDOFF_<YYYY-MM-DD>_<topic>.md` and fill in every placeholder — don't improvise the format. (Or run `/handoff`.) The template itself never changes.

This repo is the **source of truth** for LaneSight product and engineering context. Read these files first, in this order:

0. `STATUS.md` on the `context` branch (live status board) + `INBOX.md` (open cross-session items) — read these first, every session (see the freshness check above).
1. `00_CONTEXT/LANESIGHT_MASTER_CONTEXT.md`: what LaneSight is, strategy, terminology
2. `00_CONTEXT/CURRENT_STATE.md`: architecture + history of what was built (durable record, not the live task board)
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
