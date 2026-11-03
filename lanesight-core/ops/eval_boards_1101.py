#!/usr/bin/env python3
"""DEC-127 / DEC-094 board benchmark — on-device vs SERVER boards on the 7 truth-gate clips + the 11/1 set.

This is a DEVELOPER regression/parity harness (NOT runtime logic). It computes the SERVER board metrics by
running the production pipeline (lanesight_runner.analyze_clip) on each clip, and — when given the on-device gate
output — joins them and prints per-clip board deltas. The clips are real but UNLABELED for boards, so these are
engine-vs-engine PARITY deltas, not "error vs truth" (only speed/rev have sensor truth, in validation/). Grow
truth by hand-labeling boards in validation/labels/.

Usage:
  # 1. Build the server reference over all clips (writes validation/boards_server_ref_1101.json):
  source .venv/bin/activate
  python ops/eval_boards_1101.py --build-server-ref

  # 2. After an on-device gate run (xcodebuild test ... OnDeviceGateTests | tee gate.log), compare:
  python ops/eval_boards_1101.py --ondevice gate.log
"""
import argparse, json, os, sys, tempfile, pathlib

BOARD_KEYS = ['entry_board', 'arrows_board', 'laydown_board', 'board_at_7ft',
              'breakpoint_board', 'breakpoint_distance', 'entry_angle', 'launch_angle']

# The 7 truth-gate clips + the 11/1 set (IMG_8963-8981 minus 8980, which has no speed label). Union = 22 unique.
TRUTH7 = ['IMG_8751', 'IMG_8752', 'IMG_8753', 'IMG_8754', 'IMG_8964', 'IMG_8969', 'IMG_8981']
SET_1101 = [f'IMG_{n}' for n in range(8963, 8982) if n != 8980]
CLIPS = TRUTH7 + [c for c in SET_1101 if c not in TRUTH7]

DATA = pathlib.Path(os.path.expanduser('~/LaneSightData/training_videos'))
SET_DIR = DATA / '11:1 Shots'
REPO = pathlib.Path(__file__).resolve().parents[1]
REF_PATH = REPO / 'validation' / 'boards_server_ref_1101.json'


def resolve(clip: str):
    """Find a clip's .mov/.MOV in training_videos or the 11:1 Shots dir."""
    for base in (DATA, SET_DIR):
        for ext in ('.mov', '.MOV', '.mp4'):
            p = base / f'{clip}{ext}'
            if p.exists():
                return p
    return None


def server_boards(src: pathlib.Path) -> dict:
    os.environ.setdefault('LANESIGHT_FFMPEG_DECODE', '1')
    os.environ.setdefault('LANESIGHT_FRAME_CACHE_MB', '5500')
    from lanesight_runner.core import analyze_clip
    out = os.path.join(tempfile.mkdtemp(), 'o')
    try:
        rec, _probe, _t = analyze_clip(str(src), out, handed='R', timings={})
    except Exception as e:
        return {'error': f'{type(e).__name__}: {e}'}
    m = rec.get('metrics') or {}
    def cell(k):
        v = m.get(k)
        if isinstance(v, dict):
            return {'value': v.get('value'), 'status': v.get('status')}
        return {'value': v, 'status': 'ok' if v is not None else 'unavailable'}
    return {k: cell(k) for k in BOARD_KEYS}


def build_server_ref():
    ref = {}
    for clip in CLIPS:
        src = resolve(clip)
        if not src:
            print(f'{clip}: MISSING on disk', file=sys.stderr)
            ref[clip] = {'error': 'missing'}
            continue
        print(f'{clip}: analyzing {src.name} ...', file=sys.stderr)
        ref[clip] = server_boards(src)
    REF_PATH.write_text(json.dumps(ref, indent=2))
    print(f'wrote {REF_PATH} ({len(ref)} clips)')


def parse_gate_log(path: str) -> dict:
    """Pull the ONDEV_GATE_ROW JSON lines out of a gate-test log into {clip: {metrics...}}."""
    out = {}
    for line in pathlib.Path(path).read_text(errors='ignore').splitlines():
        i = line.find('ONDEV_GATE_ROW ')
        if i < 0:
            continue
        try:
            row = json.loads(line[i + len('ONDEV_GATE_ROW '):])
        except json.JSONDecodeError:
            continue
        out[row.get('clip')] = row
    return out


def compare(ondevice_log: str):
    if not REF_PATH.exists():
        sys.exit('no server ref; run --build-server-ref first')
    ref = json.loads(REF_PATH.read_text())
    dev = parse_gate_log(ondevice_log)
    print(f'{"clip":<11} {"metric":<20} {"server":>9} {"ondevice":>9} {"delta":>8}  status')
    stats = {}
    for clip in CLIPS:
        s, d = ref.get(clip, {}), dev.get(clip)
        if not d:
            print(f'{clip:<11} (no on-device row)')
            continue
        dmet = d.get('metrics_detailed') or {}
        for k in BOARD_KEYS:
            sv = (s.get(k) or {}).get('value')
            dv = (dmet.get(k) or {}).get('value') if isinstance(dmet.get(k), dict) else d.get(k)
            if sv is None or dv is None:
                print(f'{clip:<11} {k:<20} {_f(sv):>9} {_f(dv):>9} {"—":>8}  {_st(s,k)}/{_stdev(dmet,k)}')
                continue
            delta = dv - sv
            stats.setdefault(k, []).append(abs(delta))
            print(f'{clip:<11} {k:<20} {sv:>9.2f} {dv:>9.2f} {delta:>+8.2f}  {_st(s,k)}/{_stdev(dmet,k)}')
    print('\n=== median |on-device − server| per board metric ===')
    for k in BOARD_KEYS:
        xs = sorted(stats.get(k, []))
        med = xs[len(xs) // 2] if xs else None
        print(f'  {k:<20} n={len(xs):<3} median_abs_delta={med if med is None else round(med,2)}')


def _f(v):
    return '—' if v is None else (f'{v:.2f}' if isinstance(v, (int, float)) else str(v))
def _st(s, k):
    return (s.get(k) or {}).get('status', '?')
def _stdev(dmet, k):
    c = dmet.get(k)
    return c.get('status', '?') if isinstance(c, dict) else 'ok'


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--build-server-ref', action='store_true')
    ap.add_argument('--ondevice', metavar='GATE_LOG')
    a = ap.parse_args()
    if a.build_server_ref:
        build_server_ref()
    if a.ondevice:
        compare(a.ondevice)
    if not (a.build_server_ref or a.ondevice):
        ap.print_help()
