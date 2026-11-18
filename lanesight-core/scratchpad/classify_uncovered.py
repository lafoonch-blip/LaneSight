#!/usr/bin/env python3
"""Task 2: classify the clips NO engine covers by first-failing stage on the server production engine, with a
contact-sheet frame per clip, grouped by cause. Server-first (this runs the server learned/classical path)."""
import os, sys, json, glob
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np

UNCOVERED = ['IMG_8964','IMG_8965','IMG_8968','IMG_8970','IMG_8971','IMG_8972','IMG_8973','IMG_8974',
             'IMG_8975','IMG_8977','IMG_8978','IMG_8979','IMG_8981']
GATE = os.path.expanduser('~/Developer/LaneSight-shot/ios/LaneSight/Tests/GateClips')

def find(stem):
    for ext in ('.MOV','.mov'):
        p = os.path.join(GATE, stem+ext)
        if os.path.exists(p):
            return os.path.realpath(p)
    return None

def quiet(*a, **k):
    pass

# first-failing STAGE from the learned reason_code + diagnostics
def stage_of(reason, out):
    tp = out.get('track_pts', 0); npins = out.get('n_pins'); tf = out.get('t_foul')
    if reason in ('BALL_TRACK_NOT_FOUND', None) and tp < 6:
        return 'track'
    if reason in ('FOUL_CROSS_NOT_DETECTED','FOUL_CROSS_LOW_CONFIDENCE'):
        return 'foul'
    if reason in ('PIN_IMPACT_NOT_DETECTED','CONTACT_AMBIGUOUS'):
        return 'pins/contact'
    if reason == 'IMPLAUSIBLE_VALUE':
        return 'guard'
    if reason is None:
        return 'other/covered'
    return reason

from ops.production_engine import _load_detectors
dets = _load_detectors(quiet)
from ops.learned_analyze import analyze_learned
from lanesight_runner.core import analyze_clip
import tempfile, cv2

rows = []
frames_dir = '/tmp/ls_contact_frames'
os.makedirs(frames_dir, exist_ok=True)
for stem in UNCOVERED:
    src = find(stem)
    if not src:
        rows.append({'clip':stem,'stage':'MISSING'}); continue
    # classical (may raise a coded failure)
    cl_reason = None; cl_pts = None
    with tempfile.TemporaryDirectory() as td:
        try:
            rec,_p,_t = analyze_clip(src, os.path.join(td,stem), log=quiet)
            m = rec.get('metrics') or {}
            cl_reason = 'OK' if (m.get('speed_avg_foul_to_pins') or m.get('ball_speed')) else (rec.get('reason_code') or 'no_speed')
        except Exception as e:
            cl_reason = f'{type(e).__name__}:{getattr(e,"code",str(e))[:30]}'
    # learned
    out = {}
    try:
        det, mcd, pcd = dets
        out = analyze_learned(src, det, mc_detector=mcd, pin_contact_detector=pcd, log=quiet)
    except Exception as e:
        out = {'reason_code': f'{type(e).__name__}', 'track_pts':0}
    reason = out.get('reason_code')
    stage = stage_of(reason, out)
    rows.append({'clip':stem,'stage':stage,'learned_reason':reason,'track_pts':out.get('track_pts'),
                 'n_pins':out.get('n_pins'),'head_pin_row':out.get('head_pin_row'),
                 't_foul':out.get('t_foul'),'t_pins_motion':out.get('t_pins_motion'),
                 't_pins_geom':out.get('t_pins_geom'),'classical':cl_reason})
    # grab a representative frame (middle of the clip) for the contact sheet
    cap = cv2.VideoCapture(src); n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    cap.set(cv2.CAP_PROP_POS_FRAMES, max(0, n//2)); ok, fr = cap.read(); cap.release()
    if ok:
        h,w = fr.shape[:2]; sc = 320.0/max(h,w); fr = cv2.resize(fr,(int(w*sc),int(h*sc)))
        cv2.putText(fr, f'{stem} {stage}', (6,20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0,255,0), 2)
        cv2.imwrite(f'{frames_dir}/{stem}.png', fr)
    print(f"  {stem}: stage={stage} learned={reason} tpts={out.get('track_pts')} npins={out.get('n_pins')} classical={cl_reason}", flush=True)

# group
from collections import Counter, defaultdict
groups = defaultdict(list)
for r in rows: groups[r['stage']].append(r['clip'])
print('\nGROUPS:')
for s,cl in sorted(groups.items(), key=lambda kv: -len(kv[1])):
    print(f'  {s}: {len(cl)}  {cl}')
print('\nCLASSIFY_JSON ' + json.dumps({'rows':rows,'groups':{k:v for k,v in groups.items()}}))
