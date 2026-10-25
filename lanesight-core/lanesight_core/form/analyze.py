"""Form P1 contract + capture-view classifier.

The P1 metric set (FORM spec / DEC-047): swing-phase splits, swing time, approach time, step count,
ball-start step, rhythm (cadence ratio), finish hold, backswing height (relative), drift (rear, best effort).
analyze_form_clip assembles the record shape but returns every metric `unavailable` until a pose backend
is supplied — a callable `pose_backend(video, out_prefix, handed) -> {metric_key: Measurement-dict}` that a
later phase implements and validates against the training clips. No pose backend -> honest unavailable.
"""
from __future__ import annotations
from dataclasses import asdict
from ..models.shot import Measurement

FORM_VERSION = 'form-0.0.0'          # contract only; pose backend not yet implemented
_SRC = 'lanesight_form'

# (metric key, unit). Backswing height is RELATIVE (ratio), not an absolute height; drift is rear-view best effort.
# release_time (E6->E7) is the swing-timing bar's 4th segment; timing_at_slide / slide_length are surfaced as
# honest 'unavailable' tiles (still being validated — see pose._VALIDATING_REASON), never guessed.
FORM_P1 = [
    ('pushaway_time', 's'), ('backswing_time', 's'), ('downswing_time', 's'), ('release_time', 's'),
    ('swing_time', 's'), ('approach_time', 's'), ('step_count', 'count'),
    ('ball_start_step', 'index'), ('rhythm_ratio', 'ratio'), ('finish_hold', 's'),
    ('backswing_height_rel', 'ratio'), ('drift_boards', 'board'),
    ('timing_at_slide', 's'), ('slide_length', 'inch'),
]

VIEWS = ('down_lane', 'bowler_facing', 'rear', 'unknown')


def _unavailable(reason: str) -> list[dict]:
    return [asdict(Measurement(k, None, u, 0.0, 'unavailable', source=_SRC, note=reason))
            for k, u in FORM_P1]


def classify_view(features: dict) -> dict:
    """Decide the capture view from already-extracted features (video feature extraction is the deferred CV
    step). features: {lane_detected, ball_track_len, foul_line_visible, foreground_motion_px, face_toward_camera}.
    Returns {view, confidence, reason}. Confidence is deliberately modest until validated on real clips."""
    lane = features.get('lane_detected')
    track = features.get('ball_track_len', 0) or 0
    motion = features.get('foreground_motion_px', 0) or 0
    if lane and track > 0:
        return dict(view='down_lane', confidence=0.7, reason='Lane geometry and a ball track were found.')
    if not lane and motion > features.get('motion_threshold_px', 150):
        # bowler-facing vs rear can't be told apart without pose/face cues -> report the broad class, low conf
        if features.get('face_toward_camera') is True:
            return dict(view='bowler_facing', confidence=0.5, reason='No lane; large approach-side motion, facing camera.')
        return dict(view='bowler_facing', confidence=0.35,
                    reason='No lane; large approach-side motion (bowler-facing or rear — unresolved).')
    return dict(view='unknown', confidence=0.0, reason='Not enough signal to classify the capture view.')


def analyze_form_clip(video, out_prefix=None, handed=None, view=None, pose_backend=None, log=print) -> dict:
    """Form P1 analysis. With a pose_backend callable, returns its measurements; without one, returns the
    full P1 set as `unavailable` with a reason (never guessed). `view` may be passed from the capture-view
    classifier; otherwise 'unknown'."""
    view = view if view in VIEWS else 'unknown'
    extras = {}
    if pose_backend is None:
        reason = ('Form pose backend not configured — P1 metrics need pose estimation '
                  '(pending a pose dependency + validation on the training clips).')
        measurements = _unavailable(reason)
        status = 'unavailable'
    else:
        got = pose_backend(video, out_prefix, handed) or {}
        extras = got.get('_extras') or {}
        measurements = [got.get(k) or asdict(Measurement(k, None, u, 0.0, 'unavailable', source=_SRC,
                                                          note='not returned by pose backend'))
                        for k, u in FORM_P1]
        status = 'ok'
    return dict(
        form_version=FORM_VERSION, view=view, status=status,
        measurements=measurements,
        metrics={mm['metric']: mm for mm in measurements},
        handed=handed,
        # diagnostics the Form screen needs beyond the P1 metric tiles: the exported KEY POSITIONS stills,
        # the located event times, and clip fps. The form engine step adds baselines/watch/focus/footer.
        key_frames=extras.get('key_frames', []),
        events=extras.get('events', {}),
        fps=extras.get('fps'),
    )
