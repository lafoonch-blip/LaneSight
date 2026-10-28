"""Profile field validation (DEC-087). Reject bad input with a clear per-field message — never clamp — so
the app can show the server's reason inline on the field while keeping what the user typed.

Grip + PAP sane bounds are generous *sanity* limits (keep a fat-fingered entry out of the data), NOT a
fitting prescription. They bracket the full span seen in standard ball-drilling / fitting references:
  - Finger pitch is specified in fractions of an inch and rarely exceeds ~3/4"; we allow |pitch| <= 1.5".
  - Adult cut-to-cut spans run ~3.5"-5.5"; we allow 3.0"-6.0".
  - PAP ("dual-angle"/Mo Pinel layout) horizontal is ~3.5"-6.5" from grip center; we allow 0"-8".
  - PAP vertical is typically within ~1" up/down of the midline; we allow +/-2".
Refs: USBC equipment specs + mainstream fitting/layout guides (e.g. dual-angle PAP measurement). These are
bounds, not advice; a legitimate edge case outside them is handled by widening here, not by a DB constraint.
"""
from __future__ import annotations
import re
from datetime import date, datetime

MIN_AGE = 13

# (min, max) inches, inclusive. None end = unbounded on that side.
_RANGES = {
    'grip_middle_pitch_in': (-1.5, 1.5),
    'grip_span_in':         (3.0, 6.0),
    'pap_over_in':          (0.0, 8.0),
    'pap_up_in':            (-2.0, 2.0),
}

_PHONE_RE = re.compile(r'^\+?[1-9]\d{6,14}$')     # E.164-ish: optional +, 7-15 digits, no leading 0


class ProfileValidationError(Exception):
    """Carries the offending field + a user-facing message (shown inline, input preserved)."""
    def __init__(self, field: str, message: str):
        self.field = field
        self.message = message
        super().__init__(f'{field}: {message}')


def _parse_dob(value) -> date:
    s = str(value)[:10]
    try:
        return datetime.strptime(s, '%Y-%m-%d').date()
    except ValueError:
        raise ProfileValidationError('dob', 'Enter a valid date of birth.')


def _age_on(dob: date, today: date) -> int:
    return today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))


def validate_dob(value, today: date | None = None) -> date:
    today = today or date.today()
    dob = _parse_dob(value)
    if dob >= today:
        raise ProfileValidationError('dob', 'Date of birth must be in the past.')
    if _age_on(dob, today) < MIN_AGE:
        raise ProfileValidationError('dob', f'You must be at least {MIN_AGE} to use LaneSight.')
    return dob


def validate_profile_patch(patch: dict, existing: dict | None = None, today: date | None = None) -> None:
    """Validate an inbound PUT /me/profile patch. Raises ProfileValidationError on the first bad field.
    Partial updates are fine — only the fields present in `patch` are checked, except the create-time DOB
    gate below. Never mutates; the caller stores the (already normalized) patch only if this returns."""
    existing = existing or {}

    # phone (optional): empty string clears it; any other value must look like a real number.
    phone = patch.get('phone')
    if phone is not None and str(phone).strip() != '':
        if not _PHONE_RE.match(re.sub(r'[\s()\-.]', '', str(phone))):
            raise ProfileValidationError('phone', 'Enter a valid phone number, e.g. +15035551234.')

    # grip / PAP (optional): reject out-of-range, never clamp.
    for field, (lo, hi) in _RANGES.items():
        if patch.get(field) is None:
            continue
        try:
            v = float(patch[field])
        except (TypeError, ValueError):
            raise ProfileValidationError(field, 'Enter a number in inches.')
        if (lo is not None and v < lo) or (hi is not None and v > hi):
            raise ProfileValidationError(field, f'Enter a value between {lo} and {hi} inches.')

    # DOB: validate whenever present (covers create AND edit — DEC-087).
    if patch.get('dob') is not None and str(patch.get('dob')).strip() != '':
        validate_dob(patch['dob'], today=today)

    # Create-time gate: completing the profile from onboarding (which sends first_name/last_name — DEC-087)
    # requires a DOB, here or already stored. The legacy `name`/`display_name` alias does NOT trip the gate
    # (it's a compatibility path for partial edits like setting location, not the onboarding completion).
    # DEC-099: the gate applies ONLY when the profile is being created (no name stored yet). An existing
    # profile that predates the DOB gate must still be able to edit its first/last name from Profile — before
    # this, every name edit on such a profile failed with "Date of birth is required."
    names_in_patch = any(patch.get(k) for k in ('first_name', 'last_name'))
    has_dob = (patch.get('dob') and str(patch['dob']).strip() != '') or bool(existing.get('dob'))
    creating = not any(existing.get(k) for k in ('first_name', 'last_name', 'display_name'))
    if names_in_patch and creating and not has_dob:
        raise ProfileValidationError('dob', 'Date of birth is required.')

    if 'form_baseline' in patch:
        validate_form_baseline(patch.get('form_baseline'))


# DEC-099: the Form baseline the swing-timing bar compares each delivery against (FORM_BENCHMARKS §0.4).
# Phases are the engine's measured splits: pushaway = ball start (E2) → ball at hip (E3); backswing = hip →
# top of backswing (E4); downswing = top → bottom of the arc (E6); release = bottom of the arc → release (E7).
# `total` (ball start → release, = swing_time) is optional; when absent the engine sums the phases.
# Bounds are sanity limits only (keep a typo out), NOT a target: DEC-095's own plausibility gate puts the whole
# ball-start → release swing at 1.3–2.5 s, so no single phase or total can legitimately exceed 3 s.
FORM_BASELINE_PHASES = ('pushaway_time', 'backswing_time', 'downswing_time', 'release_time')
_FORM_BASELINE_MAX_S = 3.0


def validate_form_baseline(fb) -> None:
    if fb is None:
        return                                       # clears the baseline
    if not isinstance(fb, dict):
        raise ProfileValidationError('form_baseline', 'Form baseline must be an object.')
    mode = fb.get('mode')
    if mode not in ('entered', 'average'):
        raise ProfileValidationError('form_baseline', 'Choose "Use my average" or enter your timing.')
    if mode == 'average':
        return
    entered = 0
    for key in FORM_BASELINE_PHASES + ('total',):
        v = fb.get(key)
        if v is None:
            continue
        try:
            v = float(v)
        except (TypeError, ValueError):
            raise ProfileValidationError(key, 'Enter a time in seconds, e.g. 0.45.')
        if not (0 < v <= _FORM_BASELINE_MAX_S):
            raise ProfileValidationError(key, f'Enter a time between 0 and {_FORM_BASELINE_MAX_S:g} seconds.')
        if key != 'total':
            entered += 1
    if entered == 0:
        raise ProfileValidationError('form_baseline', 'Enter at least one phase time.')
