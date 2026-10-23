"""Evaluation harness (M1-14): run a folder of clips through the real at-lane analysis path
(`lanesight_runner.core.analyze_clip`) and emit a scorecard — per-clip status, timing and the key
metrics, so a change to the CV/calculations is scored on every real shot instead of guessed. This is
the harness whose absence let the '672 RPM' rev bug sit undetected: we had no per-shot scoreboard.

Faithful to production: the same trim -> HDR->SDR -> pipeline -> retry-whole-clip path the runner uses.
Clips are symlinked into the scratch out dir so every working artifact (trim/sdr/caches) lands there and
the originals are never touched or copied into the repo.

Usage:
  python examples/eval_session.py --clips "~/Developer/LaneSight/Training Videos" --out /tmp/eval
      [--handed right] [--glob '*.MOV']

Writes <out>/results.jsonl (one line per clip, flushed as each finishes) and <out>/scorecard.json,
and prints a summary table. Accuracy-vs-sensor scoring plugs in later (step 3) once Ruby ground truth
is ingested; this pass measures finish rate, failure modes, timing and the metric values themselves.
"""
import argparse, glob, json, os, time

KEY_METRICS = ['ball_speed', 'speed_release', 'speed_early', 'speed_late', 'rev_rate', 'rev_rate_lane',
               'entry_board', 'entry_angle', 'breakpoint_board', 'breakpoint_distance',
               'laydown_board', 'arrows_board', 'loft', 'launch_angle']


def pull(rec):
    ms = {m['metric']: m for m in rec.get('measurements', [])}
    out = {}
    for k in KEY_METRICS:
        m = ms.get(k)
        out[k] = None if not m else {'v': m.get('value'), 'status': m.get('status'), 'conf': m.get('confidence')}
    pins = rec.get('pins') or {}
    readable = pins.get('readable', pins.get('standing') is not None)
    out['pins'] = {'readable': readable, 'strike': pins.get('strike'),
                   'standing': pins.get('standing'), 'unread_reason': pins.get('unread_reason')}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--clips', required=True, help='directory of source clips')
    ap.add_argument('--out', required=True, help='scratch output dir (artifacts + scorecard)')
    ap.add_argument('--handed', default='right')
    ap.add_argument('--glob', default='*.MOV')
    a = ap.parse_args()

    from lanesight_runner.core import analyze_clip
    from lanesight_runner.probe import ClipError

    clips_dir = os.path.expanduser(a.clips); out_dir = os.path.expanduser(a.out)
    os.makedirs(out_dir, exist_ok=True)
    clips = sorted(glob.glob(os.path.join(clips_dir, a.glob)))
    if not clips:
        print(f"no clips matching {a.glob} in {clips_dir}"); return
    results = []
    with open(os.path.join(out_dir, 'results.jsonl'), 'w') as jl:
        for i, src in enumerate(clips, 1):
            name = os.path.splitext(os.path.basename(src))[0]
            out_prefix = os.path.join(out_dir, name)
            work = out_prefix + os.path.splitext(src)[1]        # symlink; keeps artifacts in out_dir
            try:
                if os.path.lexists(work): os.remove(work)
                os.symlink(src, work)
            except OSError:
                work = src
            t0 = time.time(); row = {'name': name}
            try:
                rec, p, timings = analyze_clip(work, out_prefix, handed=a.handed, log=lambda *_: None)
                row.update(status='done', metrics=pull(rec),
                           probe=f"{p.get('width')}x{p.get('height')} {p.get('measured_fps')}fps"
                                 f"{' HDR' if p.get('hdr') else ''}",
                           timings={k: timings.get(k) for k in ('probe_s', 'window_s', 'convert_s', 'analyze_s')},
                           total_s=round(time.time() - t0, 1), retried='windowed_error' in timings)
            except ClipError as e:
                row.update(status='rejected', error=str(e), total_s=round(time.time() - t0, 1))
            except RuntimeError as e:
                # a clear, explained failure state (bad framing / ball not tracked) — the gate allows these
                msg = str(e)
                clear = msg.startswith('lane not detected') or 'ball not tracked' in msg or 'not tracked enough' in msg
                row.update(status='unmet' if clear else 'crash', error=f'{type(e).__name__}: {msg}',
                           total_s=round(time.time() - t0, 1))
            except Exception as e:
                # unexpected shape/None crash — a robustness hole, not a clear failure state
                row.update(status='crash', error=f'{type(e).__name__}: {e}', total_s=round(time.time() - t0, 1))
            for f in glob.glob(out_prefix + '*'):                # clear artifacts + symlink; keep scratch small
                try: os.remove(f)
                except OSError: pass
            results.append(row); jl.write(json.dumps(row) + '\n'); jl.flush()
            m = row.get('metrics', {})
            spd = (m.get('ball_speed') or {}).get('v'); rev = (m.get('rev_rate') or {}).get('v')
            tail = f" speed={spd} rev={rev}" if row['status'] == 'done' else f" {row.get('error', '')}"
            print(f"[{i}/{len(clips)}] {name}: {row['status']} ({row.get('total_s')}s){tail}", flush=True)

    done = [r for r in results if r['status'] == 'done']
    by = lambda st: [r['name'] for r in results if r['status'] == st]
    sc = {'n': len(results), 'done': len(done),
          'unmet': by('unmet'), 'rejected': by('rejected'), 'crash': by('crash'),
          'rev_unavailable': [r['name'] for r in done
                              if (r['metrics'].get('rev_rate') or {}).get('status') == 'unavailable'],
          'pins_unreadable': [r['name'] for r in done if not r['metrics']['pins']['readable']],
          'finish_rate': round(len(done) / max(len(results), 1), 3)}
    json.dump({'scorecard': sc, 'results': results},
              open(os.path.join(out_dir, 'scorecard.json'), 'w'), indent=2)
    print("\n=== SCORECARD ===")
    print(f"clips={sc['n']}  done={sc['done']}  finish_rate={sc['finish_rate']:.0%}")
    if sc['crash']:    print("CRASH (robustness hole):   " + ', '.join(sc['crash']))
    if sc['unmet']:    print("UNMET (clear failure):     " + ', '.join(sc['unmet']))
    if sc['rejected']: print("REJECTED (clip refused):   " + ', '.join(sc['rejected']))
    if sc['rev_unavailable']: print("rev unavailable:           " + ', '.join(sc['rev_unavailable']))
    if sc['pins_unreadable']: print("pins unreadable:           " + ', '.join(sc['pins_unreadable']))
    print(f"\nwrote {os.path.join(out_dir, 'scorecard.json')}")


if __name__ == '__main__':
    main()
