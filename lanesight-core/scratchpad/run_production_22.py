#!/usr/bin/env python3
"""Column (c): run the server production_engine (classical-first + learned + ENGINE_DISAGREE) on the 22 labeled
clips and emit per-clip speed/err/status + totals. Mirrors OnDeviceGateTests truth. CoreML on Darwin."""
import os, sys, json, tempfile, traceback
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # lanesight-core

from ops.production_engine import analyze_production, _speed

TRUTH = {
    "IMG_8751": 17.872, "IMG_8752": 18.003, "IMG_8753": 18.275, "IMG_8754": 17.362,
    "IMG_8963": 17.74, "IMG_8964": 16.879, "IMG_8965": 17.49, "IMG_8966": 17.24, "IMG_8967": 17.12,
    "IMG_8968": 17.00, "IMG_8969": 18.139, "IMG_8970": 17.24, "IMG_8971": 17.48, "IMG_8972": 17.00,
    "IMG_8973": 17.74, "IMG_8974": 17.36, "IMG_8975": 18.00, "IMG_8976": 17.10, "IMG_8977": 16.88,
    "IMG_8978": 17.12, "IMG_8979": 17.74, "IMG_8981": 18.413,
}

GATE_DIR = os.path.expanduser("~/Developer/LaneSight-shot/ios/LaneSight/Tests/GateClips")

def find_clip(stem):
    for ext in (".MOV", ".mov"):
        p = os.path.join(GATE_DIR, stem + ext)
        if os.path.exists(p):
            return os.path.realpath(p)  # resolve symlinks
    return None

def quiet(*a, **k):
    pass

rows = []
for stem in sorted(TRUTH):
    src = find_clip(stem)
    truth = TRUTH[stem]
    if not src:
        rows.append({"clip": stem, "truth": truth, "speed": None, "err": None, "reason": "CLIP_MISSING"}); continue
    with tempfile.TemporaryDirectory() as td:
        try:
            rec = analyze_production(src, os.path.join(td, stem), log=quiet)
        except Exception as e:
            rows.append({"clip": stem, "truth": truth, "speed": None, "err": None,
                         "reason": f"CRASH:{type(e).__name__}:{e}"});
            traceback.print_exc(); continue
    sp = _speed((rec or {}).get("metrics"))
    reason = rec.get("speed_reason") or rec.get("reason_code") or (rec.get("reason_codes") or [None])[-1] \
             or rec.get("speed_source") or rec.get("status")
    err = (sp - truth) if sp is not None else None
    rows.append({"clip": stem, "truth": truth, "speed": round(sp, 3) if sp is not None else None,
                 "err": round(err, 3) if err is not None else None, "reason": reason})
    print(f"  {stem}: speed={sp} err={err} reason={reason}", flush=True)

# totals
reported = [r for r in rows if r["speed"] is not None]
within05 = [r for r in reported if abs(r["err"]) <= 0.5]
wrong = [r for r in reported if abs(r["err"]) > 1.0]   # plausible-but-wrong: reported but off > 1.0 mph
mae = (sum(abs(r["err"]) for r in reported) / len(reported)) if reported else None
summary = {"n": len(rows), "coverage": len(reported), "within_0.5": len(within05),
           "mae": round(mae, 3) if mae is not None else None,
           "plausible_but_wrong": [r["clip"] for r in wrong]}
out = {"rows": rows, "summary": summary}
print("\nPRODUCTION_22_JSON " + json.dumps(out))
print("\nSUMMARY", json.dumps(summary, indent=2))
