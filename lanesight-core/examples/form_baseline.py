"""Form MVP baseline (DEC-118) — score the Python form engine against the labeled form clips.

Runs the pose backend on every clip in validation/form_labels.json and reports, per clip and overall:
  * DEC-118 metric availability (step count, approach duration, swing events, release-vs-slide, tempo),
  * timing error vs the labels in FRAMES (ground-truth fps) and step-count exactness,
  * processing (wall) time, failure reason, and the detected/declared capture view.

Gate A (DEC-118 Friends-Beta): step count exact on >=95% of clips; swing events within +-2 frames.

Usage:
    cd lanesight-core && source .venv/bin/activate
    python examples/form_baseline.py                  # all labeled clips
    python examples/form_baseline.py IMG_8824 IMG_8846   # a subset
    LANESIGHT_FORM_CLIPS=/path/to/clips python examples/form_baseline.py

Env: LANESIGHT_FORM_GATE_FIX=1 flips the event gate to the spec-correct slide reference (DEC-095 fix).
Needs the pose model (~/LaneSightData/models/pose_landmarker_heavy.task) and the MediaPipe 'form' extra.
"""
from __future__ import annotations
import json, os, sys, time, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_CORE = os.path.dirname(HERE)
LABELS = os.path.join(REPO_CORE, 'validation', 'form_labels.json')
RAW_LABELS = os.path.join(REPO_CORE, 'validation', 'labels', 'form_events.json')
CLIP_DIR = os.environ.get('LANESIGHT_FORM_CLIPS', os.path.expanduser('~/LaneSightData/training_videos'))
# clips can live in subfolders of the training-videos tree
CLIP_SUBDIRS = ['', 'Form Videos', '11:1 Shots']
GATE_FRAMES = 2            # DEC-118: swing events within +-2 frames
TOL_UNAVAIL_PCT = 20      # DEC-118 coverage gate: <=20% of supported-view metrics unavailable

# engine event key -> ground-truth label key (DEC-094 Form Gate A mapping, extended with E5 slide start)
EVENT_MAP = [
    ('E2', 'E2_ball_start_s', 'ball start'),
    ('E4', 'E4_backswing_top_s', 'backswing top'),
    ('E5', 'E5_slide_start_s', 'slide start'),
    ('E7', 'E7_release_s', 'release'),
    ('E8', 'E8_slide_stop_s', 'slide stop'),
]
# DEC-118 gated swing events (ball start, top of backswing, release, slide stop)
DEC118_EVENTS = {'E2', 'E4', 'E7', 'E8'}


def find_clip(clip_id: str):
    for sub in CLIP_SUBDIRS:
        for ext in ('MOV', 'mov', 'MP4', 'mp4'):
            p = os.path.join(CLIP_DIR, sub, f'{clip_id}.{ext}')
            if os.path.exists(p):
                return p
    return None


def fps_for(clip_id: str, labels_raw: dict, engine_fps) -> float:
    c = (labels_raw.get('clips') or {}).get(clip_id) or {}
    f = c.get('fps')
    return float(f) if f else float(engine_fps or 30.0)


def main(argv):
    with open(LABELS) as fh:
        labels = json.load(fh)['clips']
    labels_raw = {}
    if os.path.exists(RAW_LABELS):
        with open(RAW_LABELS) as fh:
            labels_raw = json.load(fh)
    want = [a for a in argv if not a.startswith('-')]
    clip_ids = want or sorted(labels)

    from lanesight_core.form import pose
    from lanesight_core.form.analyze import analyze_form_clip
    backend = pose.build_backend(log=lambda *a: None)
    gate_fix = os.environ.get('LANESIGHT_FORM_GATE_FIX') == '1'
    print(f'pose model: {pose.POSE_MODEL_PATH}')
    print(f'gate reference: {"E5 slide plant (LANESIGHT_FORM_GATE_FIX=1)" if gate_fix else "E8 hold_start (production default)"}')
    print(f'gate: swing events +-{GATE_FRAMES} frames, step count exact\n')

    rows = []
    for cid in clip_ids:
        lab = labels[cid]
        path = find_clip(cid)
        print('=' * 94)
        print(f'{cid}  view(label)={lab.get("view")}  ({path or "NOT FOUND"})')
        if not path:
            rows.append(dict(clip=cid, ok=False, reason='clip file not found'))
            print('  SKIP: clip file not found')
            continue
        t0 = time.time()
        try:
            rec = analyze_form_clip(path, out_prefix=None, handed='right', view=None, pose_backend=backend,
                                    log=lambda *a: None)
        except Exception as e:
            dt = time.time() - t0
            rows.append(dict(clip=cid, ok=False, reason=f'{type(e).__name__}: {e}', wall_s=dt))
            print(f'  ERROR after {dt:.1f}s: {type(e).__name__}: {e}')
            continue
        dt = time.time() - t0
        # analyze_form_clip surfaces the located event times directly on the record (gated events included).
        events = rec.get('events') or {}
        fps = fps_for(cid, labels_raw, rec.get('fps'))
        view_detected = rec.get('view')
        status = rec.get('status')
        metrics = rec.get('metrics') or {}

        # --- timing error vs labels (frames) ---
        ev_rows = []
        for ekey, lkey, name in EVENT_MAP:
            det = events.get(ekey)
            gt = lab.get(lkey)
            if det is None or gt is None:
                ev_rows.append((name, ekey, det, gt, None, None))
                continue
            derr = det - gt
            ferr = derr * fps
            ev_rows.append((name, ekey, det, gt, derr, ferr))

        sc = metrics.get('step_count', {})
        sc_val = sc.get('value')
        sc_gt = lab.get('step_count')
        sc_exact = (sc_val == sc_gt) if sc_val is not None else False

        rows.append(dict(clip=cid, ok=True, status=status, wall_s=dt, fps=fps,
                         view_label=lab.get('view'), view_detected=view_detected,
                         step_val=sc_val, step_gt=sc_gt, step_exact=sc_exact,
                         events=ev_rows, metrics=metrics,
                         events_gate=rec.get('view_info')))

        print(f'  status={status}  view(detected)={view_detected}  fps={fps:.2f}  wall={dt:.1f}s')
        print(f'  step_count: {sc_val} vs {sc_gt}  [{"EXACT" if sc_exact else "MISS"}]  ({sc.get("status")})')
        print(f'  {"event":14s} {"det(s)":>8s} {"label(s)":>9s} {"Δs":>7s} {"Δframes":>8s}  gate')
        for name, ekey, det, gt, derr, ferr in ev_rows:
            if det is None or gt is None:
                g = 'n/a' if gt is None else ('NULL' if det is None else '')
                ds = '   n/a' if det is None else f'{det:7.3f}'
                gs = '   n/a' if gt is None else f'{gt:8.3f}'
                print(f'  {name:14s} {ds:>8s} {gs:>9s} {"":>7s} {"":>8s}  {g}'
                      + (f'  [{ekey} DEC-118]' if ekey in DEC118_EVENTS else ''))
                continue
            within = abs(ferr) <= GATE_FRAMES
            tag = 'PASS' if within else 'FAIL'
            print(f'  {name:14s} {det:8.3f} {gt:9.3f} {derr:+7.3f} {ferr:+8.1f}  [{tag}]'
                  + (f'  {ekey} DEC-118' if ekey in DEC118_EVENTS else ''))

    # ---------- summary ----------
    print('\n' + '=' * 94)
    print('FORM MVP BASELINE SUMMARY (DEC-118)')
    done = [r for r in rows if r.get('ok')]
    n = len(rows)
    print(f'  clips: {n} ({len(done)} analyzed, {n - len(done)} failed/not-found)')
    if done:
        exact = sum(1 for r in done if r['step_exact'])
        print(f'  step count exact: {exact}/{len(done)} ({100*exact/len(done):.0f}%)  [gate >=95%]')
        # per DEC-118 event frame-error aggregate
        print('  swing-event frame error (|Δframes|), per event across clips with both values:')
        for ekey, lkey, name in EVENT_MAP:
            errs = []
            nulls = 0
            for r in done:
                row = next((e for e in r['events'] if e[1] == ekey), None)
                if row is None:
                    continue
                det, gt, ferr = row[2], row[3], row[5]
                if gt is None:
                    continue
                if det is None:
                    nulls += 1
                elif ferr is not None:
                    errs.append(abs(ferr))
            scored = len(errs)
            passn = sum(1 for e in errs if e <= GATE_FRAMES)
            med = sorted(errs)[len(errs)//2] if errs else None
            mx = max(errs) if errs else None
            gate_tag = ' DEC-118' if ekey in DEC118_EVENTS else ''
            meds = f'{med:.1f}' if med is not None else '  -'
            mxs = f'{mx:.1f}' if mx is not None else '  -'
            print(f'    {name:14s} ({ekey}{gate_tag}): scored {scored}, null {nulls},'
                  f' within±{GATE_FRAMES}f {passn}/{scored}, median {meds}f, max {mxs}f')
        wall = [r['wall_s'] for r in done if r.get('wall_s')]
        if wall:
            print(f'  processing time: median {sorted(wall)[len(wall)//2]:.1f}s, max {max(wall):.1f}s (Mac, pose heavy)')
        print('  views analyzed:', ', '.join(sorted({f"{r['view_label']}→{r['view_detected']}" for r in done})))
    fails = [r for r in rows if not r.get('ok')]
    if fails:
        print('  failures:')
        for r in fails:
            print(f'    {r["clip"]}: {r.get("reason")}')
    return rows


if __name__ == '__main__':
    main(sys.argv[1:])
