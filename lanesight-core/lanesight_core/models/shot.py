"""Shot record contract (schema v1). This is what the API returns for GET /shots/{id} and what the virtual
replay renders. Every value is a Measurement with source, confidence, status and algorithm version (DEC-022,
UI Spec §7: never show a precise number without minimum confidence)."""
from __future__ import annotations
from dataclasses import dataclass, field, asdict

SCHEMA_VERSION = 'shot-1.0'
ALGO_VERSION = "lanesight-cv-0.6.0"

@dataclass
class Measurement:
    metric: str
    value: float | None
    unit: str
    confidence: float = 0.0              # 0..1
    status: str = 'ok'                   # ok | low_confidence | unavailable | calibrated_estimate
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
    context: dict = field(default_factory=dict)      # session_id, ball_id, pattern_id, lane, intent, frame/roll
    schema_version: str = SCHEMA_VERSION
    def to_dict(self):
        d = asdict(self); d['metrics'] = {x['metric']: x for x in d['measurements']}; return d
    def value(self, metric):
        for x in self.measurements:
            if x.metric == metric: return x.value
        return None
