#!/usr/bin/env python3
"""DEC-130/131 production speed engine: classical-first, learned fallback, with an engine-disagreement guard.

The production shot analysis runs the CLASSICAL pipeline (sub-pixel accurate where it locks on) AND the LEARNED
engine (CoreML/torch ball+lane detector + trained pins class + the DEC-131 pin-contact changepoint, which covers
camera positions classical can't). The two speeds are reconciled:

  - both present & agree (<= DISAGREE_MPH):  keep CLASSICAL (sub-pixel), it is the reference.
  - both present & disagree (> DISAGREE_MPH): speed UNAVAILABLE, reason ENGINE_DISAGREE (never pick one -> zero
    plausible-but-wrong).
  - only one present:                         use it (learned extends coverage; classical stays authoritative where
                                              it alone succeeds).
  - neither:                                  classical's own failure record.

Everything else in the record (trajectory, pins, boards, rev) comes from whichever engine produced the headline so
the downstream consumers see a coherent shot. This is the single entry the server API and the on-device parity
harness both target."""
from __future__ import annotations
import os

DISAGREE_MPH = 0.5
SPEED_KEYS = ('speed_avg_foul_to_pins', 'ball_speed')

_DETECTORS = None


def _load_detectors(log=lambda *a, **k: None):
    """Lazy module-singleton load of the learned detectors (CoreML ball/lane + torch pins + pin-contact changepoint).
    Paths come from LS_DEC130_DIR (default ~/LaneSightData/dec130). Returns None if the models are absent (the engine
    then degrades to classical-only, so a box without the models still runs)."""
    global _DETECTORS
    if _DETECTORS is not None:
        return _DETECTORS or None
    base = os.environ.get('LS_DEC130_DIR', os.path.expanduser('~/LaneSightData/dec130'))
    ball = f'{base}/coreml/BallLaneDetector.mlpackage'
    mc = f'{base}/model_mc/detector_mc.pt'
    mc_ml = f'{base}/coreml/BallPinsDetector.mlpackage'
    try:
        from ops.detector_integrate import LearnedDetector
        from ops.mc_detect import MCDetector
        from ops.pin_contact import PinContactDetector
        if not os.path.exists(ball):
            log(f'[prod-engine] no ball model at {ball}; classical-only'); _DETECTORS = False; return None
        det = LearnedDetector(mlpackage=ball)
        mcd = MCDetector(mlpackage=mc_ml) if os.path.exists(mc_ml) else (MCDetector(ckpt=mc) if os.path.exists(mc) else None)
        pcd = PinContactDetector(offset_f=float(os.environ.get('LS_PINCONTACT_OFFSET', '3.0')))
        _DETECTORS = (det, mcd, pcd)
        return _DETECTORS
    except Exception as e:
        log(f'[prod-engine] detector load failed ({type(e).__name__}: {e}); classical-only'); _DETECTORS = False
        return None


def _speed(metrics):
    """Headline speed from a metrics dict, tolerating both {k: v} and {k: {'value': v}} shapes."""
    if not metrics:
        return None
    for k in SPEED_KEYS:
        x = metrics.get(k)
        v = x.get('value') if isinstance(x, dict) else x
        if v is not None:
            return float(v)
    return None


def _set_speed_unavailable(rec, reason):
    """Null the headline speed in a classical record and record the reason (keeps the rest of the record intact)."""
    m = rec.get('metrics') or {}
    for k in SPEED_KEYS:
        if k in m:
            m[k] = None
    rec['metrics'] = m
    rec.setdefault('reason_codes', []).append(reason)
    rec['speed_reason'] = reason
    return rec


def analyze_production(src, out_prefix, handed=None, log=print, learned=True, **kw):
    """Run classical + learned and reconcile (see module docstring). Returns a JSON-safe ShotRecord dict. Signature
    matches default_analyzer's callers via analyze_clip; `learned=False` (or LS_LEARNED_FALLBACK=0) = classical-only."""
    from lanesight_runner.core import analyze_clip
    classical = None
    try:
        classical, _probe, _timings = analyze_clip(src, out_prefix, handed=handed, log=log)
    except Exception as e:
        log(f'[prod-engine] classical failed: {type(e).__name__}: {e}')
    c_speed = _speed((classical or {}).get('metrics'))

    dets = _load_detectors(log) if (learned and os.environ.get('LS_LEARNED_FALLBACK', '1') != '0') else None
    l_speed = None; l_cross = None; learned_out = None
    if dets:
        det, mcd, pcd = dets
        try:
            from ops.learned_analyze import analyze_learned
            learned_out = analyze_learned(src, det, mc_detector=mcd, pin_contact_detector=pcd, log=log)
            l_speed = _speed(learned_out.get('metrics'))               # authoritative headline (guarded)
            l_cross = learned_out.get('speed_besteffort')              # best-effort, for the disagreement guard only
        except Exception as e:
            log(f'[prod-engine] learned failed: {type(e).__name__}: {e}')

    # --- reconcile ---
    # Disagreement guard: compare classical against the learned speed (its headline, else its best-effort estimate).
    # When they disagree by > DISAGREE_MPH the clip is withheld (ENGINE_DISAGREE) — never pick one. This catches
    # clips where classical alone is wrong but the learned headline withheld (e.g. IMG_8968).
    l_for_cmp = l_speed if l_speed is not None else l_cross
    if c_speed is not None and l_for_cmp is not None and abs(c_speed - l_for_cmp) > DISAGREE_MPH:
        log(f'[prod-engine] ENGINE_DISAGREE classical={c_speed:.2f} learned={l_for_cmp:.2f} -> unavailable')
        return _set_speed_unavailable(classical, 'ENGINE_DISAGREE')
    if c_speed is not None and l_speed is not None:
        log(f'[prod-engine] agree classical={c_speed:.2f} learned={l_speed:.2f} -> classical')
        classical['speed_source'] = 'classical'
        return classical
    if c_speed is not None:
        classical['speed_source'] = 'classical'
        return classical
    if l_speed is not None:
        # classical gave no speed: overlay the learned speed onto the classical record (keeps lane/traj context),
        # or return the learned record if classical wholly failed.
        base = classical if isinstance(classical, dict) and classical.get('metrics') is not None else {'metrics': {}, 'status': 'analyzed'}
        m = base.get('metrics') or {}
        m['speed_avg_foul_to_pins'] = round(l_speed, 2); m['ball_speed'] = round(l_speed, 2)
        base['metrics'] = m; base['speed_source'] = 'learned'
        base['reason_code'] = learned_out.get('reason_code')
        return base
    # neither: classical's own failure record (or a coded failure if classical crashed)
    return classical if classical is not None else {'metrics': {}, 'status': 'failed', 'reason_code': 'NO_SPEED'}
