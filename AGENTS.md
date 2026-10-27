# Instructions for AI assistants (Claude, ChatGPT, others)

## Quick start: where the truth is (read before anything else)
**One central location: this repo.** Every change to context, decisions, designs (as synced files) and code lands here. Anything elsewhere is either an upstream editor that syncs into this repo, or a read-only mirror.

| Area | Source of truth | Not a source |
|---|---|---|
| Newest state of everything | GitHub `lafoonch-blip/LaneSight`, `main` (plus open PR / feature branches). LaneSight no longer depends on Shayne's Mac (2026-10-27) | Your memory of an earlier chat; an old clone |
| Running backend | Google Cloud Run `lanesight-api` (us-east1) + Supabase `europwryibstnmipbvam`; runbook `03_ENGINEERING/DEPLOY_CLOUDRUN.md` | The Mac launchd/Tailscale service (retired) |
| Decisions | `00_CONTEXT/DECISIONS.md` (highest DEC number wins) | Older docs, `99_ARCHIVE/` |
| What's being built now | `00_CONTEXT/CURRENT_STATE.md`, `03_ENGINEERING/DEV_BUILD_PLAN.md` | — |
| Dev Build v0 screens | `02_DESIGN/dev_build_v0/` (synced from the Claude Design canvas "LaneSight Dev Build v0 Screens") | Figma screens, old mockups |
| Visual standards (color, type, spacing) | Figma "01 - Design Standards" page | Colors in old docs/UI Spec v1 |
| Logo and app/web icons | Figma Design Components › "Brand standards" → exported to `02_DESIGN/brand/` (DEC-054) | **The LS monogram concept: never use it** |
| Later-version (target-state) screens | Figma "Lanesight - Product UX - Design" | — |
| Code | `lanesight-core/` (Python CV/API), `ios/LaneSight/` (SwiftUI) | — |
| Mirror (read-only, may lag) | claude.ai LaneSight Project docs | Never edit it as the source. The Google Drive copies are retired (frozen 2026-10-14, labeled STALE) |

### Freshness check (do this first, every session)
1. `git fetch && git status && git log --oneline -5 origin/main`. Work from `origin/main` (or the feature branch you were asked to continue), not an old clone or a pasted file.
2. Read the last ~5 entries of `DECISIONS.md` and the top of `CURRENT_STATE.md`.
3. Compare any doc you were handed (mirror, upload, paste) by its `Version` / `Last Updated` header against the repo copy. If the repo is newer, use the repo.
4. Before building UI: `git diff 02_DESIGN/` and read `02_DESIGN/dev_build_v0/README.md` (changelog at the bottom).
5. Several AI sessions may work at once. Re-read a file right before you edit it; never overwrite changes you didn't read.

### When you change something
- Write it to this repo in the same session (doc, DEC entry, design sync or code). A change that lives only in a chat, canvas, Figma or a mirror is not done.
- Decisions: add a new DEC; mark the old one superseded. Docs: bump `Version` / `Last Updated`.
- Commit on a feature branch; push to GitHub only when Shayne says so (never to `main` directly). Work that only exists in a local or cloud-session clone is not saved: say so in your report. After it lands on `main`, re-sync the claude.ai Project docs (don't update the retired Drive copies).
- Report what you changed and anything you could not update.

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
