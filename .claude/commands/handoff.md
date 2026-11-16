---
description: Write a repeatable handoff for the next session from the fixed template
---

Create a handoff for the next Claude Code session using the FIXED template at
`03_ENGINEERING/HANDOFF_TEMPLATE.md`. Topic (optional): $ARGUMENTS

Do this:
1. Read `03_ENGINEERING/HANDOFF_TEMPLATE.md`. Keep its section order and headings EXACTLY — never invent a new format.
2. Gather the real current state (verify, don't guess):
   - Branches + short SHAs, what each is, pushed/merged status: `git branch -a`, `git log --oneline -1 <branch>`, `git rev-list --count origin/<b>..<b>`.
   - Live Cloud Run revision + region/project + relevant env flags: `gcloud run services describe lanesight-api --region us-east1 --format='value(status.latestReadyRevisionName)'` and its env vars.
   - Migrations applied to live (and any NOT applied / duplicate prefixes): the Supabase migrations list.
   - Open work, what's deferred/gated, and traps (parallel worktrees, duplicate migration numbers, fixes living on two branches).
3. Copy the template to `03_ENGINEERING/HANDOFF_<YYYY-MM-DD>_<topic>.md` (slug the topic from $ARGUMENTS or the current work; use today's date) and fill EVERY `<...>` placeholder with verified facts. Delete a section only if truly N/A — write "N/A", don't drop the heading.
4. Do NOT push, apply a migration, deploy, or merge — a handoff is a write-up only.
5. Report the file path and a 3-line plain-English summary of what the next session should do first. Keep it short.
