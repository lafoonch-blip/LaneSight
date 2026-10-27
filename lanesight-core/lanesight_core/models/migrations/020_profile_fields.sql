-- 020 Profile fields (DEC-087): separate names, phone, and bowler-level grip + PAP. Additive + idempotent.
-- DEC-087 makes First/Last/Email/Phone/DOB separate editable fields and moves grip (middle pitch, span) and
-- PAP (over, up) from "target state" (DEC-074) into MVP, stored per bowler. All measurements are in INCHES.
-- RLS is unchanged (profiles is already owner read/write). DO NOT apply to live — that is Shayne's step.

alter table profiles
  add column if not exists first_name            text,
  add column if not exists last_name             text,
  add column if not exists phone                 text,
  -- Grip + PAP in inches. Signed where a direction exists (forward/reverse pitch, PAP up/down). Ranges are
  -- validated in the API (lanesight_api/profile_validation.py), not as DB constraints, so a future fitting
  -- edge case can't be locked out by a migration — see that module for the cited sane bounds.
  add column if not exists grip_middle_pitch_in  numeric,
  add column if not exists grip_span_in          numeric,
  add column if not exists pap_over_in           numeric,
  add column if not exists pap_up_in             numeric;

comment on column profiles.first_name is 'bowler given name (DEC-087). display_name is maintained as "First Last" for existing readers.';
comment on column profiles.last_name  is 'bowler family name (DEC-087).';
comment on column profiles.phone      is 'optional contact phone, E.164-ish (DEC-087). Never the login email.';
comment on column profiles.grip_middle_pitch_in is 'middle-finger pitch in inches, signed (+forward / -reverse) (DEC-074/087).';
comment on column profiles.grip_span_in          is 'finger-to-thumb span in inches, cut-to-cut (DEC-074/087).';
comment on column profiles.pap_over_in           is 'PAP horizontal distance from grip center, inches (DEC-074/087).';
comment on column profiles.pap_up_in             is 'PAP vertical offset, inches, signed (+up / -down) (DEC-074/087).';

-- Backfill first/last from the existing combined display_name (split on the FIRST space; everything after the
-- first space is the last name). Only fills rows that don't already have a first_name.
update profiles
set first_name = split_part(display_name, ' ', 1),
    last_name  = nullif(regexp_replace(display_name, '^\S+\s*', ''), '')
where first_name is null
  and display_name is not null
  and btrim(display_name) <> '';
