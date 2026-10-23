"""Run the Form P1 pose backend on the four training clips and validate against the reference tables.

Usage:
    cd lanesight-core && source .venv/bin/activate
    python examples/analyze_form.py                 # default clip dir + scratch output
    python examples/analyze_form.py /path/to/clips  # override the clip directory
    LANESIGHT_FORM_OUT=/tmp/foo python examples/analyze_form.py

Needs the pose model at ~/LaneSightData/models/pose_landmarker_heavy.task (or $LANESIGHT_POSE_MODEL) and the
MediaPipe "form" extra. Prints a computed-vs-reference table with within-tolerance flags and writes one JSON
per clip to a scratch directory (never into the repo or the Training Videos folder).

Reference tables: 02_RESEARCH/TRAINING_VIDEOS_CALIBRATED_METRICS.md (footwork) and
TRAINING_VIDEOS_2026-10-20_ANALYSIS.md (swing timing). These are unvalidated research results (no Ruby ground
truth), so treat the flags as "reproduces the prototype", not "accurate in absolute terms".
"""
from __future__ import annotations
import json, os, sys, tempfile
from lanesight_core.form import pose
from lanesight_core.form.analyze import analyze_form_clip

CLIP_DIR = os.environ.get('LANESIGHT_FORM_CLIPS',
                          os.path.expanduser('~/Developer/LaneSight/Training Videos'))
OUT_DIR = os.environ.get('LANESIGHT_FORM_OUT', os.path.join(tempfile.gettempdir(), 'lanesight_form'))

# Reference values (from the research tables). Swing splits are session means; footwork is per clip.
REF = {
    'IMG_8845': dict(fps=120, slowmo=True, step_count=4, intervals=[0.37, 0.41, 0.64],
                     first_to_release=1.47, slide_to_release=0.05),
    'IMG_8846': dict(fps=30, slowmo=False, step_count=4, intervals=[0.37, 0.37, 0.57],
                     first_to_release=1.42, slide_to_release=0.12),
    'IMG_8847': dict(fps=60, slowmo=False, step_count=4, intervals=[0.37, 0.40, 0.58],
                     first_to_release=1.47, slide_to_release=0.12),
    'IMG_8848': dict(fps=60, slowmo=False, step_count=4, intervals=[0.43, 0.37, 0.60],
                     first_to_release=1.45, slide_to_release=0.05),
}
# swing-timing references (session means) shared by all clips, plus the per-clip values where published
SWING_REF = dict(backswing_time=0.78, downswing_time=0.40, ball_at_hip_to_release=1.21, tempo_ratio=0.51)
SWING_REF_PER = {
    'IMG_8845': dict(backswing_time=0.78, downswing_time=0.37, ball_at_hip_to_release=1.17, tempo_ratio=0.47),
    'IMG_8846': dict(backswing_time=0.73, downswing_time=0.40, ball_at_hip_to_release=1.17, tempo_ratio=0.55),
    'IMG_8847': dict(backswing_time=0.75, downswing_time=0.40, ball_at_hip_to_release=1.19, tempo_ratio=0.53),
    'IMG_8848': dict(backswing_time=0.87, downswing_time=0.42, ball_at_hip_to_release=1.32, tempo_ratio=0.48),
}


def flag(computed, ref, fps, scale=1.0):
    """✓ within tolerance (max(0.05 s, 1 frame)), ~ within 2x, ✗ otherwise. `scale` widens the band for ratios."""
    if computed is None or ref is None:
        return ' '
    tol = max(0.05, 1.0 / fps) * scale
    d = abs(computed - ref)
    return '✓' if d <= tol else ('~' if d <= 2 * tol else '✗')


def row(label, computed, ref, status, fps, scale=1.0, unit=''):
    c = '   n/a' if computed is None else f'{computed:6.2f}'
    r = '  n/a' if ref is None else f'{ref:5.2f}'
    return f'  {label:24s} {c} {unit:5s} vs ref {r}  [{flag(computed, ref, fps, scale)}]  ({status})'


def main():
    clips = ['IMG_8845', 'IMG_8846', 'IMG_8847', 'IMG_8848']
    os.makedirs(OUT_DIR, exist_ok=True)
    _raw = pose.build_backend(log=lambda *a: None)
    _cache = {}

    def backend(video, out_prefix=None, handed=None):   # memoize: pose extraction is ~40 s/clip
        if video not in _cache:
            _cache[video] = _raw(video, out_prefix, handed)
        return _cache[video]
    print(f'pose model: {pose.POSE_MODEL_PATH}')
    print(f'scratch output: {OUT_DIR}\n')
    summary = []
    for name in clips:
        path = os.path.join(CLIP_DIR, name + '.MOV')
        print('=' * 78)
        print(f'{name}   ({path})')
        if not os.path.exists(path):
            print('  SKIP: clip not found')
            continue
        try:
            rec = analyze_form_clip(path, handed='right', view='rear', pose_backend=backend)
        except Exception as e:
            print(f'  ERROR: {type(e).__name__}: {e}')
            continue
        metrics = rec['metrics']
        # analyze_form_clip surfaces only the FORM_P1 keys; the diagnostic extras live on the backend result
        # (memoized, so this does not re-run pose).
        ex = backend(path).get('_extras', {})
        fpsr = ex.get('fps', REF[name]['fps'])
        ref = REF[name]
        sref = SWING_REF_PER.get(name, SWING_REF)

        # footwork
        sc = metrics['step_count']['value']
        sc_flag = '✓' if sc == ref['step_count'] else '✗'
        print(f'  slo-mo detected: {ex.get("slowmo", {}).get("is_slowmo")} '
              f'(factor {ex.get("slowmo", {}).get("factor")})')
        print(f'  {"step_count":24s} {sc} vs ref {ref["step_count"]}  [{sc_flag}]  '
              f'({metrics["step_count"]["status"]})')
        iv = ex.get('step_intervals_values') or []
        iv_flags = [flag(iv[i] if i < len(iv) else None, ref['intervals'][i], fpsr)
                    for i in range(len(ref['intervals']))]
        print(f'  {"step_intervals (s)":24s} '
              f'{[round(x,2) for x in iv]} vs ref {ref["intervals"]}  {iv_flags}')
        print(row('first_step->release', _v(ex, 'first_step_to_release'), ref['first_to_release'],
                  _s(ex, 'first_step_to_release'), fpsr, unit='s'))
        print(row('slide_plant->release', _v(ex, 'slide_to_release'), ref['slide_to_release'],
                  _s(ex, 'slide_to_release'), fpsr, unit='s'))
        # swing splits
        print(row('backswing_time', metrics['backswing_time']['value'], sref['backswing_time'],
                  metrics['backswing_time']['status'], fpsr, unit='s'))
        print(row('downswing_time', metrics['downswing_time']['value'], sref['downswing_time'],
                  metrics['downswing_time']['status'], fpsr, unit='s'))
        print(row('ball_at_hip->release', _v(ex, 'ball_at_hip_to_release'), sref['ball_at_hip_to_release'],
                  _s(ex, 'ball_at_hip_to_release'), fpsr, unit='s'))
        print(row('rhythm_ratio (tempo)', metrics['rhythm_ratio']['value'], sref['tempo_ratio'],
                  metrics['rhythm_ratio']['status'], fpsr, scale=2.0))
        # other P1 (no tight reference)
        for k in ('swing_time', 'approach_time', 'finish_hold', 'backswing_height_rel'):
            mm = metrics[k]
            print(f'  {k:24s} {("   n/a" if mm["value"] is None else f"{mm['value']:6.2f}")} {mm["unit"]:5s}'
                  f'           ({mm["status"]})')
        # out-of-scope
        print(f'  {"drift_boards":24s} unavailable  ({metrics["drift_boards"]["note"][:60]}...)')

        # write JSON (full record + extras) to scratch
        out = os.path.join(OUT_DIR, name + '.form.json')
        with open(out, 'w') as fh:
            json.dump(dict(clip=name, record=rec, extras=ex), fh, indent=2, default=str)
        summary.append((name, sc == ref['step_count']))
    print('=' * 78)
    print('JSON written to', OUT_DIR)
    print('step_count exact:', ', '.join(f'{n} {"ok" if ok else "MISS"}' for n, ok in summary))


def _v(ex, key):
    mm = ex.get(key)
    return mm.get('value') if isinstance(mm, dict) else None


def _s(ex, key):
    mm = ex.get(key)
    return mm.get('status') if isinstance(mm, dict) else 'unavailable'


if __name__ == '__main__':
    if len(sys.argv) > 1:
        CLIP_DIR = sys.argv[1]
    main()
