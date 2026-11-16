# LaneSight handoff — <TOPIC> (<YYYY-MM-DD>)

<!--
HOW TO USE (this template never changes):
1. Copy this file to 03_ENGINEERING/HANDOFF_<YYYY-MM-DD>_<TOPIC>.md
2. Fill every <...> placeholder. Delete a section only if it's truly N/A (say "N/A", don't drop the heading).
3. Keep the section ORDER and HEADINGS exactly — that's what makes handoffs scannable and repeatable.
4. Facts only: real branch names, revisions, migration numbers. No "should be" — verify before you write it.
-->

## Read first
Repo `~/Developer/LaneSight`. Read `AGENTS.md`, `00_CONTEXT/CURRENT_STATE.md`, and the last ~8 DECs in `00_CONTEXT/DECISIONS.md`.
Rules: don't ask permission — do + report; keep reports short/plain; the only hard gates are **push** and **applying a live migration** (get an explicit OK). Backend tests must pass before committing.

## What's live right now
- **Cloud Run:** rev `<rev-name>` (region `<region>`, project `<project-ref>`), built from branch `<branch>`. Health `<ok/…>`.
- **Flags:** `<e.g. precheck shadow/enforce; KEEP_CLIPS off; any LANESIGHT_* env that matters>`.
- **Migrations applied to live:** `<through NNN; note any duplicate prefixes>`. NOT applied: `<…>`.

## Branches (state of each)
For every branch in play: `<name> @ <short-sha>` — one line on what it is, what's pushed, what's applied/deployed, merged or not.
- `<branch>` @ `<sha>` — `<summary>` · pushed `<y/n>` · migration `<applied?>` · deployed `<rev/no>` · merged to `<target>` `<y/n>`.

## What's done
Bullet the finished work (committed + pushed). One line each; link the DEC.

## Next round of work (do this)
Numbered, actionable. Each item: the goal + the concrete first step. Mark which need Shayne's go (push / live migration / deploy / enforce flips).
1. `<…>`
2. `<…>`

## Deferred / gated (don't start)
What's intentionally on hold and why (e.g. waiting on Phase-2, waiting on labels, enforce gate pending data). So the next session doesn't redo or prematurely ship it.

## Watch out for
Traps: parallel sessions/worktrees, duplicate migration numbers, fixes that exist on two branches, flaky env, anything easy to break.

## Done-when
How the next session knows this round is complete (tests green, deployed rev X, on-device checklist passed, PR merged, etc.) + what to put in the final report.
