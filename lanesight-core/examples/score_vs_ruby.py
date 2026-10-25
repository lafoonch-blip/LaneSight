"""Score a harness run against Ruby ground truth (M5-05 shot matching + per-metric variance).

Ruby has no export, so its per-shot values are transcribed from the Sessions-list screenshots into a
truth JSON (see validation/ruby_live_session_2026-10-15.json). Videos are matched to Ruby shots by
wall-clock: each clip's QuickTime creation time (recording start) plus the bowler's ~30 s set-up-to-throw
delay lands within a shot-spacing of the Ruby shot time. A clip that falls in a Ruby logging gap stays
unmatched (reported), never force-matched.

Usage:
  python examples/score_vs_ruby.py --clips "~/LaneSightData/training_videos" \
      --truth validation/ruby_live_session_2026-10-15.json \
      --scorecard /path/to/eval/scorecard.json [--window 70]
"""
import argparse, glob, json, os, statistics as st, subprocess


def secs_after_noon(t):                       # "H:MM:SS" 12-hour, all PM
    h, m, s = (int(x) for x in t.split(':')); return (h % 12) * 3600 + m * 60 + s


def creation_secs(path):
    out = subprocess.run(['ffprobe', '-v', 'quiet', '-print_format', 'json',
                          '-show_entries', 'format_tags=com.apple.quicktime.creationdate', path],
                         capture_output=True, text=True).stdout
    try:
        cd = json.loads(out)['format']['tags']['com.apple.quicktime.creationdate']   # 2026-10-15T12:34:15-0400
        hms = cd.split('T')[1][:8]; h, m, s = (int(x) for x in hms.split(':'))
        return (h % 12) * 3600 + m * 60 + s
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--clips', required=True); ap.add_argument('--truth', required=True)
    ap.add_argument('--scorecard', required=True); ap.add_argument('--window', type=int, default=70)
    ap.add_argument('--glob', default='*.MOV')
    a = ap.parse_args()
    truth = json.load(open(os.path.expanduser(a.truth)))
    rshots = [dict(r, t=secs_after_noon(r['time'])) for r in truth['shots'] if r.get('rpm') is not None]
    scard = json.load(open(os.path.expanduser(a.scorecard)))
    res = {r['name']: r for r in scard['results']}

    clips = sorted(glob.glob(os.path.join(os.path.expanduser(a.clips), a.glob)))
    created = {}
    for c in clips:
        cs = creation_secs(c)
        if cs is not None: created[os.path.splitext(os.path.basename(c))[0]] = cs
    matches, used = {}, set()
    for name, cs in sorted(created.items(), key=lambda kv: kv[1]):      # earliest first; greedy nearest
        cands = sorted((abs(r['t'] - (cs + 30)), r) for r in rshots
                       if 0 < r['t'] - cs <= a.window and r['t'] not in used)
        if cands:
            r = cands[0][1]; used.add(r['t']); matches[name] = r
    unmatched = [n for n in created if n not in matches]
    print(f"matched {len(matches)}/{len(created)} videos; unmatched (Ruby logging gap): {unmatched}\n")

    def score(metric, ruby_key, unit, gate):
        rows = [(n, (res[n]['metrics'][metric] or {}), m) for n, m in sorted(matches.items())
                if res.get(n, {}).get('status') == 'done']
        errs, bias = [], []
        print(f"=== {metric} (ruby {ruby_key}, gate ±{gate} {unit}) ===")
        for n, mv, r in rows:
            v = mv.get('v')
            if v is None:
                print(f"  {n}: {mv.get('status')}  (ruby {r[ruby_key]})"); continue
            d = v - r[ruby_key]; errs.append(abs(d)); bias.append(d)
            print(f"  {n}: video {v:.2f}  ruby {r[ruby_key]}  Δ{d:+.2f}" + ('  <-- off' if abs(d) > 2 * gate else ''))
        if errs:
            se = sorted(errs); p90 = se[min(len(se) - 1, int(0.9 * len(se)))]
            print(f"  MAE={st.mean(errs):.2f}  median={st.median(errs):.2f}  p90={p90:.2f}  "
                  f"bias={st.mean(bias):+.2f}  within-gate {sum(e <= gate for e in errs)}/{len(errs)}\n")
        return errs

    score('ball_speed', 'mph', 'mph', 0.5)
    revs = [(n, (res[n]['metrics']['rev_rate'] or {}).get('v')) for n, m in sorted(matches.items())
            if res.get(n, {}).get('status') == 'done' and (res[n]['metrics']['rev_rate'] or {}).get('v')]
    score('rev_rate', 'rpm', 'rpm', 30)
    bins = {}
    for n, v in revs: bins.setdefault(round(v, 1), []).append(n)
    print("rev snapping (distinct video values → shots sharing each):")
    for v, ns in sorted(bins.items()):
        print(f"  {v}: {len(ns)} {ns}")


if __name__ == '__main__':
    main()
