# Feedback Store — one table for all feedback (dev, beta, live)
Status: APPROVED DIRECTION (DEC-059) · implementation not started
Version: 1.0
Last Updated: 2026-10-25
Owner: Shayne
Governing: DEC-059 (supersedes the storage parts of DEC-053 and DEC-058)

## 1. Goal
Collect every piece of bowler feedback in one place, across dev, beta and the live app, and keep it so Shayne can analyze and act on it whenever he wants.
- Feedback is **write-and-keep**. Nothing in the app reads it at runtime, and it never changes a measurement, rule, score or recommendation by itself. Any change it leads to goes through the normal process (owner review → rules version / DEC → release).
- Feedback outlives the shot or session it was written about.

## 2. What goes in
| `source` | Where it comes from | Fields used |
|---|---|---|
| `shot_note` | Shot card › "Your notes on this shot" (DEC-058) | `text`, `tags` |
| `session_feedback` | Session-end sheet (DEC-053) | `rating` 1–5, `tags`, `text`, `diagnostics` |
| `advice_rating` | 👍 / 👎 on next-shot advice (Shot card) and the form focus (Form results) | `thumbs`, optional `text` |
| `form_note` | Reserved for notes on Form results (not designed yet) | `text`, `tags` |
| `general` | Reserved: Settings › Send feedback (not designed yet) | `text`, `tags`, `diagnostics` |

## 3. Table `feedback`
| Column | Type | Notes |
|---|---|---|
| `id` | uuid pk | |
| `created_at`, `updated_at` | timestamptz | Autosaved notes update the same row |
| `source` | text enum (§2) | |
| `app_phase` | text: `dev` · `beta` · `live` | From the build / Beta–Prod toggle at the time of writing |
| `app_version`, `core_version`, `rules_version`, `formula_version` | text | What produced the results the feedback is about |
| `user_id` | uuid null, FK → users **ON DELETE SET NULL** | Null once the account is deleted (§5) |
| `user_ref` | text | Stable pseudonymous id (e.g. salted hash), kept after deletion so one person's feedback can still be grouped |
| `session_id`, `shot_id`, `recommendation_id` | uuid null, FKs **ON DELETE SET NULL** | Links while the source exists |
| `capture_mode` | `shot` · `form` · null | |
| `is_upload` | bool | Standalone upload (DEC-055) vs live session |
| `rating` | smallint 1–5 null | |
| `thumbs` | `up` · `down` · null | |
| `tags` | text[] | Shot tags: Hit my target, Missed left, Missed right, Pocket, Light, High, Felt good, Pulled it. Session tags: Bug, Metric looked wrong, Advice, Camera/upload, Workflow, Idea |
| `text` | text | Free text |
| `context` | jsonb | **Snapshot at write time** of what the feedback is about: the shot's measured metrics with status/confidence (speed, rev, boards at laydown/arrows/breakpoint/entry, entry angle, form checkpoints…), the advice shown, the intent. Lets "what I saw" vs "what we measured" be compared even after the shot is deleted |
| `diagnostics` | jsonb | Timings, errors, device, capture fps (when the user allows it) |
| `triage_status` | `new` · `reviewed` · `actioned` · `dismissed` | **Owner-only** |
| `owner_notes`, `action_ref` | text | **Owner-only**: what was done (rules version, DEC, task id) |
| `anonymized_at` | timestamptz null | Set when the account is deleted |

Indexes: `(created_at)`, `(source, app_phase)`, `(user_ref)`, `(shot_id)`, `(session_id)`, `(triage_status)`.

## 4. Access (RLS)
- A bowler can **insert** feedback and **read / update their own** rows while their account exists (to edit an autosaved note). They can't read anyone else's or see the triage columns.
- Only the owner role (`rules_admin`) can read everything and write the triage columns.
- **No client delete.** Removing feedback is an owner action only.

## 5. Shot, session and account deletion
- **Deleting a shot or session** keeps its feedback. `shot_id` / `session_id` become null, and the `context` snapshot keeps the comparison possible.
- **Deleting the account** keeps the feedback but **anonymizes** it:
  - `user_id` is set to null and `anonymized_at` is set.
  - Free text is kept, so the privacy policy must say feedback is retained in de-identified form.
  - Identifying fields in `diagnostics` (device name, email, IP) are removed.
- The account-deletion flow stays compliant with App Store guideline 5.1.1(v), which requires deleting the account and its personal data. De-identified feedback retained for product improvement must be disclosed in the privacy policy and App Privacy label.
- If a bowler asks for their feedback to be fully erased, the owner deletes their rows by `user_ref`.

## 6. Analysis (owner, offline)
- **Export:** an owner CSV / SQL view over `feedback` joined to `context`, filterable by phase, source, version, tag and date.
- **Example comparisons:**
  - Tag "Light" vs measured entry board outside 16–19 → agreement rate.
  - Tag "Missed right" vs measured arrows miss direction.
  - 👎 advice rate by rule id and version.
  - Session ratings by app version.
- **Triage:** mark rows reviewed / actioned with a link to the change. Nothing feeds back automatically.

## 7. Migration from what exists
- `session_feedback` (migration 008, live in Supabase): copy existing rows into `feedback` with `source = 'session_feedback'`. Then either replace the table with a view or keep writing only to `feedback`. No data loss.
- Advice 👍 / 👎 is currently `recommendation_outcomes` / `PATCH /shots/{id}`. Also write a `feedback` row with `source = 'advice_rating'`; the outcome tables keep their measurement role.
- New API: `PUT /shots/{id}/note` and `POST /feedback` write `feedback` rows. The CSV export reads from `feedback`.
