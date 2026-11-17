#!/usr/bin/env python3
"""Parse ONDEV_GATE_ROW lines from an xcodebuild test log and emit per-clip speed/err/status + totals.
Usage: python3 parse_gate.py <logfile> <label>"""
import sys, json

TRUTH = {
    "IMG_8751": 17.872, "IMG_8752": 18.003, "IMG_8753": 18.275, "IMG_8754": 17.362,
    "IMG_8963": 17.74, "IMG_8964": 16.879, "IMG_8965": 17.49, "IMG_8966": 17.24, "IMG_8967": 17.12,
    "IMG_8968": 17.00, "IMG_8969": 18.139, "IMG_8970": 17.24, "IMG_8971": 17.48, "IMG_8972": 17.00,
    "IMG_8973": 17.74, "IMG_8974": 17.36, "IMG_8975": 18.00, "IMG_8976": 17.10, "IMG_8977": 16.88,
    "IMG_8978": 17.12, "IMG_8979": 17.74, "IMG_8981": 18.413,
}

path, label = sys.argv[1], sys.argv[2]
rows = {}
with open(path, errors="replace") as f:
    for line in f:
        i = line.find("ONDEV_GATE_ROW ")
        if i < 0:
            continue
        try:
            r = json.loads(line[i + len("ONDEV_GATE_ROW "):].strip())
        except Exception:
            continue
        rows[r.get("clip")] = r

out = []
for stem in sorted(TRUTH):
    r = rows.get(stem)
    truth = TRUTH[stem]
    if r is None:
        out.append({"clip": stem, "truth": truth, "speed": None, "err": None, "reason": "NOT_IN_LOG", "lat": None}); continue
    sp = r.get("speed_avg_foul_to_pins")
    err = (sp - truth) if isinstance(sp, (int, float)) else None
    reason = r.get("reason_code") or r.get("note") or r.get("basis")
    out.append({"clip": stem, "truth": truth, "speed": round(sp, 3) if isinstance(sp, (int, float)) else None,
                "err": round(err, 3) if err is not None else None, "reason": reason,
                "lat": round(r["latency_s"], 1) if isinstance(r.get("latency_s"), (int, float)) else None})

reported = [r for r in out if r["speed"] is not None]
within05 = [r for r in reported if abs(r["err"]) <= 0.5]
wrong = [r for r in reported if abs(r["err"]) > 1.0]
mae = (sum(abs(r["err"]) for r in reported) / len(reported)) if reported else None
summary = {"label": label, "n": len(out), "coverage": len(reported), "within_0.5": len(within05),
           "mae": round(mae, 3) if mae is not None else None,
           "plausible_but_wrong": [r["clip"] for r in wrong],
           "covered_clips": sorted(r["clip"] for r in reported),
           "max_lat": max((r["lat"] for r in reported if r["lat"] is not None), default=None)}
print(f"GATE_PARSE_JSON[{label}] " + json.dumps({"rows": out, "summary": summary}))
print(f"\n=== {label} ===")
for r in out:
    print(f'  {r["clip"]}: speed={r["speed"]} err={r["err"]} reason={r["reason"]} lat={r["lat"]}')
print("SUMMARY", json.dumps(summary, indent=2))
