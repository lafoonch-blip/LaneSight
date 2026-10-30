"""Structured analysis failures (DEC-086).

Every place the analysis pipeline can fail raises an `AnalysisFailure` carrying a stable `code`, the
`stage` it failed at, a technical `message`, and `diagnostics` (the numbers that explain it). The server owns
the user-facing copy here (FAILURE_COPY) so it can change without an app release; the app only ever shows
`user_title` / `user_message` / `tip`, never the exception class or raw message.

`AnalysisFailure` subclasses `RuntimeError` so existing `pytest.raises(RuntimeError, ...)` tests and string
checks keep working.
"""
from __future__ import annotations

# The pipeline stages a failure can be attributed to.
STAGES = ('decode', 'stabilize', 'lane', 'track', 'impact', 'metrics', 'sanity', 'form_pose', 'storage', 'internal')


class AnalysisFailure(RuntimeError):
    """A pipeline failure with a stable code + the numbers behind it. The str() stays human-readable
    (code + message) for back-compat with log lines and `pytest.raises(match=...)`."""

    def __init__(self, code: str, message: str, stage: str = 'internal', diagnostics: dict | None = None):
        self.code = code
        self.stage = stage if stage in STAGES else 'internal'
        self.message = message
        self.diagnostics = diagnostics or {}
        super().__init__(f'{code}: {message}')

    def as_dict(self) -> dict:
        """The {code, stage, user_title, user_message, tip} block the API attaches to a failed job/shot."""
        copy = FAILURE_COPY.get(self.code, FAILURE_COPY['INTERNAL_ERROR'])
        return {'code': self.code, 'stage': self.stage,
                'user_title': copy['user_title'], 'user_message': copy['user_message'], 'tip': copy.get('tip')}


def failure_block(code: str, stage: str = 'internal') -> dict:
    """Build the user-facing {code, stage, user_title, user_message, tip} for a bare code (e.g. a legacy row
    or a code recovered from a stored shot). Falls back to the generic copy for an unknown code."""
    copy = FAILURE_COPY.get(code, FAILURE_COPY['INTERNAL_ERROR'])
    return {'code': code, 'stage': stage,
            'user_title': copy['user_title'], 'user_message': copy['user_message'], 'tip': copy.get('tip')}


# code -> user_title / user_message / tip (capture advice). Keep the copy plain-language and honest; never
# reference boards/code internals the bowler wouldn't know. `tip` may be None when there's no useful advice.
FAILURE_COPY: dict[str, dict] = {
    'LANE_NOT_DETECTED_NO_WOOD': {
        'user_title': "We couldn't find the lane",
        'user_message': "The lane wasn't clear enough in the video for us to read it.",
        'tip': "Make sure the whole lane is in frame and well lit, and record in a standard (non-HDR) format.",
    },
    'LANE_NOT_DETECTED_NO_EDGES': {
        'user_title': "We couldn't find the lane",
        'user_message': "We saw wood but couldn't line up the lane's edges, so we can't measure your shot.",
        'tip': "Set the camera behind the approach, square to the lane, with the whole lane in view.",
    },
    'FOUL_LINE_NOT_IN_VIEW': {
        'user_title': "The foul line isn't in the shot",
        'user_message': "The foul line needs to be visible for us to measure your line and speed.",
        'tip': "Raise the camera or pull it back so the foul line is in view at the bottom of the frame.",
    },
    'LANE_NOT_DETECTED': {
        'user_title': "We couldn't find the lane",
        'user_message': "We couldn't lock onto the lane in this clip.",
        'tip': "Record from behind the approach with the whole lane — foul line to pins — in frame.",
    },
    'LANE_GEOMETRY_UNUSABLE': {
        'user_title': "The camera angle was too tough",
        'user_message': "The lane's angle in the video made it impossible to read reliably.",
        'tip': "Reshoot with the camera behind the lane and square to it, not off to the side.",
    },
    'BALL_TRACK_NOT_FOUND': {
        'user_title': "We couldn't follow the ball",
        'user_message': "We couldn't track the ball well enough in this clip to measure the shot.",
        'tip': "Keep the ball in view with good contrast, and nothing crossing in front of the camera.",
    },
    'PIN_IMPACT_NOT_DETECTED': {
        'user_title': "We couldn't see the ball reach the pins",
        'user_message': "We lost the ball before it got to the pins and couldn't read its revs either, so nothing could be measured.",
        'tip': "Make sure the pins are visible and the ball stays in view all the way down the lane.",
    },
    'TRACK_TOO_SPARSE_FOR_SPEED': {
        'user_title': "We lost the ball early",
        'user_message': "We couldn't follow the ball through the first 30 feet, so speed can't be measured.",
        'tip': "Keep the foul line through the arrows in clear view, with nothing crossing in front of the camera.",
    },
    'IMPOSSIBLE_SPEED_SCALE': {
        'user_title': "The ball was lost down the lane",
        'user_message': "The ball wasn't tracked all the way to the pins, so speed and entry can't be trusted.",
        'tip': "Reshoot with the ball visible to the pins — less glare, and nothing crossing the back of the lane.",
    },
    'TIMING_FRAME_MISMATCH': {
        'user_title': "The video timing didn't line up",
        'user_message': "The clip's frames and timing didn't match, so we couldn't measure it accurately.",
        'tip': "Re-export the clip as H.264 / Most Compatible and try again.",
    },
    'FORM_DELIVERY_NOT_ISOLATED': {
        'user_title': "We couldn't find your whole delivery",
        'user_message': "The swing timing didn't add up, so none of the key positions could be trusted.",
        'tip': "Start recording before your first step and keep your whole approach, swing and release in frame.",
    },
    'FORM_POSE_BACKEND_UNAVAILABLE': {
        'user_title': "Form analysis isn't available",
        'user_message': "We couldn't run form analysis on our side for this clip.",
        'tip': None,
    },
    'VIDEO_DECODE_FAILED': {
        'user_title': "We couldn't open the video",
        'user_message': "This clip's format couldn't be read for analysis.",
        'tip': "Re-export the clip as H.264 / Most Compatible and try again.",
    },
    'VIDEO_NO_FRAMES': {
        'user_title': "The video looked empty",
        'user_message': "We couldn't read any frames from this clip.",
        'tip': "Record a fresh clip and try again.",
    },
    'UNKNOWN_LEGACY': {
        'user_title': "Couldn't analyze",
        'user_message': "This clip couldn't be analyzed.",
        'tip': None,
    },
    'INTERNAL_ERROR': {
        'user_title': "Something went wrong on our side",
        'user_message': "This one's on us — please try again.",
        'tip': None,
    },
}
