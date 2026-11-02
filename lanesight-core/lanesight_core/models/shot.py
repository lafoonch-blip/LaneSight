"""Shot record contract (schema v1). This is what the API returns for GET /shots/{id} and what the virtual
replay renders. Every value is a Measurement with source, confidence, status and algorithm version (DEC-022,
UI Spec §7: never show a precise number without minimum confidence)."""
from __future__ import annotations
from dataclasses import dataclass, field, asdict

SCHEMA_VERSION = 'shot-1.0'
# 0.7.0 (2026-10-31, DEC-113/DEC-103): canonical SDR decode (deterministic YUV->BGR) changed CV outputs
# materially vs 0.6.0 (server speeds were ~14% low on the old cv2 decode). The version bump is the engine
# provenance marker: measurements tagged < 0.7.0 are quarantined ("legacy") so stats never mix the two engines.
# 0.7.1 (2026-11-02, DEC-117): detect_impact no longer clamps the pin-impact up to a `far` tracked point that
# sits PAST the pins (ball tracked into the pit on a strike) — the clamp now only defers to `far` when the pin
# hotness fired BEFORE the ball entered the ROI. Fixes IMG_8752's foul->pins average (15.49 -> 17.85 vs truth
# 18.00). Only shots whose ball was TRACKED PAST IMPACT change; all other shots are byte-identical to 0.7.0,
# so 0.7.0 data is NOT quarantined wholesale — only the retained clips that change are re-run (DEC-117 decision).
ALGO_VERSION = "lanesight-cv-0.7.1"

@dataclass
class Measurement:
    metric: str
    value: float | None
    unit: str
    confidence: float = 0.0              # 0..1
    status: str = 'ok'                   # ok | low_confidence | best_effort | unavailable | calibrated_estimate
    source: str = 'lanesight_video'      # lanesight_video | sensor:<vendor> | scoring:<system> | manual
    algorithm_version: str = ALGO_VERSION
    note: str | None = None
    uncertainty: float | None = None     # ± in `unit`: the honest resolution band (e.g. rev's frame-lag quantum)

def m(metric, value, unit, conf, note=None, min_conf=0.5, status=None, source='lanesight_video', uncertainty=None):
    if value is None: return Measurement(metric, None, unit, 0.0, 'unavailable', source, note=note)
    st = status or ('ok' if conf >= min_conf else 'low_confidence')
    unc = None if uncertainty is None else round(float(uncertainty), 3)
    return Measurement(metric, round(float(value), 3), unit, round(float(conf), 2), st, source, note=note, uncertainty=unc)

@dataclass
class ShotRecord:
    shot_id: str
    handed: str
    video: dict
    events: dict
    measurements: list[Measurement]
    trajectory: dict
    key_points: dict
    pins: dict | None
    insights: dict | None = None
    spare_plan: dict | None = None
    sensor: dict | None = None
    capture_quality: dict | None = None              # {far_lane: ok|limited, reason} — DEC-061 plausibility gate
    stage_report: dict | None = None                 # DEC-122: per-stage {status: ok|failed|skipped, reason, diagnostics}
    context: dict = field(default_factory=dict)      # session_id, ball_id, pattern_id, lane, intent, frame/roll
    schema_version: str = SCHEMA_VERSION
    def to_dict(self):
        d = asdict(self); d['metrics'] = {x['metric']: x for x in d['measurements']}; return d
    def value(self, metric):
        for x in self.measurements:
            if x.metric == metric: return x.value
        return None
