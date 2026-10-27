# Data Governance & Security Strategy
Status: PROPOSED
Version: 1.1
Last Updated: 2026-10-26

## Retention
Raw clips downloaded/uploaded for transient analysis and deleted; **no retained video clips**. Retain only approved Form key frames and avatars under private controls. Form overlays are drawn from stored confidence-gated landmarks, not burned into frames (DEC-082). Define and test temporary object cleanup on success, error, timeout and retry.

## Feedback
One retained feedback table for dev/beta/live, with retained contextual snapshots; account deletion anonymizes/de-identifies feedback (DEC-059). Free text may still identify people: verify actual deletion/scrubbing before privacy promises. Staged accounts cannot distort real insights (DEC-063).

## Security
Verify Cloud Run authorization, Supabase RLS, user-level isolation, access logs, managed secrets, signed short-lived links, account deletion, under-13 gating and limited staff access. Require affirmative sharing consent for future coaches/team. Legal friends-Beta P0 scope awaits owner approval. No consumer sensor flows (DEC-070).