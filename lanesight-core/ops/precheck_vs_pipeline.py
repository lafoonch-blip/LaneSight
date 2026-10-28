"""DEC-092 precheck-vs-pipeline agreement on the benchmark manifest. For each present clip: the precheck
verdict (ok True/False/None) vs the FULL pipeline outcome (analyzed / failed + code). The rule to enforce:
precheck must reject (ok=False) ZERO clips the full pipeline passes (analyzed). Any such clip is a FALSE
REJECTION and blocks enforcement."""
import json, os, signal
from pathlib import Path
from lanesight_core.cv.precheck import precheck
from lanesight_runner.core import analyze_clip

CLIPS = os.path.expanduser('~/LaneSightData/training_videos')
man = json.load(open('ops/perf_manifest.json'))['clips']
rows = []
for e in man:
    name = e['clip']; p = str(Path(CLIPS) / name)
    if not os.path.exists(p):
        rows.append((name, 'missing', '', '')); continue
    pc = precheck(p)
    pc_ok = pc.get('ok')
    pc_s = 'reject' if pc_ok is False else ('pass' if pc_ok is True else 'unknown')
    pc_code = pc.get('code', '')
    # full pipeline outcome
    signal.signal(signal.SIGALRM, lambda s, f: (_ for _ in ()).throw(TimeoutError())); signal.alarm(500)
    try:
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            analyze_clip(p, os.path.join(td, 'x'), log=lambda *a: None)
        outcome, ocode = 'analyzed', ''
    except Exception as ex:
        outcome, ocode = 'failed', (getattr(ex, 'code', None) or type(ex).__name__)
    finally:
        signal.alarm(0)
    false_reject = (pc_ok is False and outcome == 'analyzed')
    rows.append((name, pc_s, pc_code, f'{outcome} {ocode}'.strip(), 'FALSE_REJECT' if false_reject else ''))
    print(f"{name:16} precheck={pc_s:8} {pc_code:28} pipeline={outcome} {ocode}"
          + ('   <<< FALSE REJECTION' if false_reject else ''), flush=True)

fr = [r for r in rows if len(r) > 4 and r[4] == 'FALSE_REJECT']
print(f"\nFALSE REJECTIONS (precheck rejected but pipeline analyzed): {len(fr)}")
json.dump(rows, open('ops/perf_reports/precheck_vs_pipeline.json', 'w'), indent=2)
print("wrote ops/perf_reports/precheck_vs_pipeline.json")
