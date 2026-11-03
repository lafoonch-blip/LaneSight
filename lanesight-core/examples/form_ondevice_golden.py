"""On-device Form parity golden (DEC-118 / DEC-121 / on-device Form port).

Runs the lanesight_core Python form reference on the labeled form clips and freezes a machine-readable
golden the Swift on-device engine must reproduce. For each clip it records:
  * fps, detected view,
  * every located event time (E2 ball-start, E4 backswing top, E5 slide start, E6 bottom-of-arc,
    E7 release, E8 slide stop, first_step, slide_plant, hold_start, hold_end) and the swing source,
  * foot strikes + per-step intervals + step count,
  * slo-mo verdict,
  * every FORM_P1 metric (value / status / confidence / display),
  * a compact diagnostics block (torso scale, approach burst, setup-hold end, slide foot),
  * the per-event frame error vs the ground-truth labels (form_labels.json + form_steps_labels.json).

Output: validation/form_ondevice_golden.json (committed — small; the parity target for OnDeviceFormGateTests).

Usage:
    cd lanesight-core
    ~/Developer/LaneSight/lanesight-core/.venv/bin/python examples/form_ondevice_golden.py
    python examples/form_ondevice_golden.py IMG_8824          # a subset
    LANESIGHT_FORM_CLIPS=/path python examples/form_ondevice_golden.py

Needs the pose model (~/LaneSightData/models/pose_landmarker_heavy.task) and MediaPipe (the 'form' extra).
"""
from __future__ import annotations
import json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_CORE = os.path.dirname(HERE)
# This worktree's code must win over any editable install on the interpreter's path.
sys.path.insert(0, REPO_CORE)

LABELS = os.path.join(REPO_CORE, 'validation', 'form_labels.json')
STEP_LABELS = os.path.join(REPO_CORE, 'validation', 'form_steps_labels.json')
OUT = os.path.join(REPO_CORE, 'validation', 'form_ondevice_golden.json')
CLIP_DIR = os.environ.get('LANESIGHT_FORM_CLIPS', os.path.expanduser('~/LaneSightData/training_videos'))
CLIP_SUBDIRS = ['', 'Form Videos', '11:1 Shots']
HELD_OUT = {'IMG_8980'}            # DEC-121: 8980 stays held out of the pass set

# engine event key -> ground-truth label key (DEC-094 / DEC-118 Form Gate A mapping)
EVENT_MAP = [
    ('E2', 'E2_ball_start_s', 'ball start'),
    ('E4', 'E4_backswing_top_s', 'backswing top'),
    ('E5', 'E5_slide_start_s', 'slide start'),
    ('E7', 'E7_release_s', 'release'),
    ('E8', 'E8_slide_stop_s', 'slide stop'),
]
DEC118_EVENTS = {'E2', 'E4', 'E7', 'E8'}       # swing events gated to +-2 frames
FORM_P1_KEYS = ['pushaway_time', 'backswing_time', 'downswing_time', 'release_time', 'swing_time',
                'approach_time', 'step_count', 'ball_start_step', 'rhythm_ratio', 'finish_hold',
                'backswing_height_rel', 'drift_boards', 'timing_at_slide', 'slide_length']


def find_clip(clip_id: str):
    for sub in CLIP_SUBDIRS:
        for ext in ('MOV', 'mov', 'MP4', 'mp4'):
            p = os.path.join(CLIP_DIR, sub, f'{clip_id}.{ext}')
            if os.path.exists(p):
                return p
    return None


def _metric(metrics: dict, key: str):
    m = (metrics or {}).get(key) or {}
    return {'value': m.get('value'), 'status': m.get('status'),
            'confidence': m.get('confidence'), 'display': m.get('display')}


def main(argv):
    with open(LABELS) as fh:
        labels = json.load(fh)['clips']
    step_labels = {}
    if os.path.exists(STEP_LABELS):
        with open(STEP_LABELS) as fh:
            step_labels = json.load(fh).get('clips', {})
    want = [a for a in argv if not a.startswith('-')]
    clip_ids = want or sorted(labels)

    from lanesight_core.form import pose
    from lanesight_core.form.analyze import analyze_form_clip
    from lanesight_core.form import fundamentals
    backend = pose.build_backend(log=lambda *a: None)
    print(f'pose model: {pose.POSE_MODEL_PATH}')
    print(f'backend version: {pose.POSE_BACKEND_VERSION}')
    print(f'writing golden: {OUT}\n')

    golden = {
        '_source': 'examples/form_ondevice_golden.py — Python form reference, the on-device parity target',
        'backend_version': pose.POSE_BACKEND_VERSION,
        'fundamentals_version': fundamentals.FUNDAMENTALS_VERSION,
        'gate': {'events_frames': 2, 'per_plant_frames': 3, 'dec118_events': sorted(DEC118_EVENTS),
                 'step_count': 'exact', 'runtime_s': 30, 'held_out': sorted(HELD_OUT)},
        'clips': {},
    }

    for cid in clip_ids:
        lab = labels.get(cid, {})
        slab = step_labels.get(cid, {})
        path = find_clip(cid)
        print('=' * 90)
        print(f'{cid}  view(label)={lab.get("view")}  held_out={cid in HELD_OUT}  ({path or "NOT FOUND"})')
        if not path:
            golden['clips'][cid] = {'ok': False, 'reason': 'clip file not found'}
            print('  SKIP: clip not found')
            continue
        t0 = time.time()
        try:
            raw = backend(path, None, 'right')               # full pose.analyze dict incl. _extras
            rec = analyze_form_clip(path, out_prefix=None, handed='right', view=None,
                                    pose_backend=lambda *a, **k: raw, log=lambda *a: None)
        except Exception as e:
            dt = time.time() - t0
            golden['clips'][cid] = {'ok': False, 'reason': f'{type(e).__name__}: {e}', 'wall_s': round(dt, 2)}
            print(f'  ERROR after {dt:.1f}s: {type(e).__name__}: {e}')
            continue
        dt = time.time() - t0
        extras = raw.get('_extras') or {}
        events = extras.get('events') or {}
        fps = float(slab.get('fps') or rec.get('fps') or 30.0)
        metrics = rec.get('metrics') or {}

        # event frame error vs labels
        ev_err = {}
        for ekey, lkey, name in EVENT_MAP:
            det, gt = events.get(ekey), lab.get(lkey)
            if det is None or gt is None:
                ev_err[ekey] = {'det_s': det, 'label_s': gt, 'd_frames': None}
            else:
                ev_err[ekey] = {'det_s': round(det, 4), 'label_s': gt,
                                'd_frames': round((det - gt) * fps, 2)}

        # per-plant step timing vs form_steps_labels (+-3 frames)
        strikes = [s[0] for s in (extras.get('strikes') or [])]
        gt_steps = [slab.get(f'step{i}_s') for i in range(1, 7)]
        gt_steps = [s for s in gt_steps if s is not None]

        sc = metrics.get('step_count', {})
        g = {
            'ok': True, 'view_label': lab.get('view'), 'view_detected': rec.get('view'),
            'status': rec.get('status'), 'fps': round(fps, 4), 'wall_s': round(dt, 2),
            'swing_source': extras.get('swing_source'),
            'events': {k: (None if v is None else round(v, 4)) for k, v in events.items()},
            'event_frame_error': ev_err,
            'strikes_s': [round(s, 4) for s in strikes],
            'step_intervals_s': extras.get('step_intervals_values'),
            'step_count': {'value': sc.get('value'), 'status': sc.get('status'),
                           'label': lab.get('step_count')},
            'step_labels_s': gt_steps,
            'slowmo': {'is_slowmo': (extras.get('slowmo') or {}).get('is_slowmo'),
                       'factor': (extras.get('slowmo') or {}).get('factor')},
            'metrics': {k: _metric(metrics, k) for k in FORM_P1_KEYS},
            'measured_positions': {k: {'id': v.get('id'), 'value': v.get('value'),
                                       'status': v.get('status'), 'display': v.get('display')}
                                   for k, v in (rec.get('measured_positions') or {}).items()},
            'stage_report': rec.get('stage_report'),
        }
        golden['clips'][cid] = g

        # console summary
        print(f'  status={g["status"]}  view={g["view_detected"]}  fps={fps:.2f}  wall={dt:.1f}s'
              f'  swing_src={g["swing_source"]}')
        scv, scl = sc.get('value'), lab.get('step_count')
        print(f'  step_count: {scv} vs {scl} [{"EXACT" if scv == scl else "MISS"}] ({sc.get("status")})')
        for ekey, lkey, name in EVENT_MAP:
            e = ev_err[ekey]
            tag = 'DEC118' if ekey in DEC118_EVENTS else '      '
            if e['d_frames'] is None:
                print(f'    {name:14s} {ekey} {tag}  det={e["det_s"]}  label={e["label_s"]}  Δf=  n/a')
            else:
                within = abs(e['d_frames']) <= 2
                print(f'    {name:14s} {ekey} {tag}  det={e["det_s"]:.3f}  label={e["label_s"]:.3f}'
                      f'  Δf={e["d_frames"]:+.1f}  [{"PASS" if within else "FAIL"}]')

    with open(OUT, 'w') as fh:
        json.dump(golden, fh, indent=2, sort_keys=False)
        fh.write('\n')
    print('\n' + '=' * 90)
    done = [c for c in golden['clips'].values() if c.get('ok')]
    print(f'wrote {OUT}  ({len(done)}/{len(golden["clips"])} clips analyzed)')
    return golden


if __name__ == '__main__':
    main(sys.argv[1:])
