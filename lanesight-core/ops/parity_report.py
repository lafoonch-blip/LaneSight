"""DEC-128 item 3: per-clip on-device-vs-server parity table.

Joins ops/parity_manifest.json (SERVER analysis_metric_outcome per shot) with the ONDEV_GATE_ROW lines printed by
OnDeviceGateTests on device (the iPhone engine's metrics_detailed + stage report + diag). For every clip/metric
where the SERVER produced a value, classifies the iPhone result:
  MATCH        both measured, within tolerance            (good)
  UNAVAIL+why  server measured, iPhone unavailable + reason (acceptable — honest miss)
  NO-REASON    server measured, iPhone unavailable with NO reason_code   (gate FAIL — item 2)
  DISAGREE     both measured but outside tolerance         (gate FAIL)
  IMPLAUSIBLE  iPhone value physically out of range        (gate FAIL — must be zero)

Usage: python3 ops/parity_report.py <gate_output.txt>
"""
import os, sys, json

MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'parity_manifest.json')
TOL = {'ball_speed': 1.5, 'speed_avg_foul_to_pins': 1.5, 'rev_rate': 75.0, 'laydown_board': 2.0,
       'board_at_7ft': 2.0, 'arrows_board': 2.0, 'breakpoint_board': 3.0, 'entry_board': 3.0,
       'entry_angle': 2.0, 'launch_angle': 1.5, 'loft': 1.0}
BOUNDS = {'board': (1, 39), 'speed': (8, 30), 'rev': (100, 700)}


def _band(metric):
    if 'board' in metric:
        return BOUNDS['board']
    if metric == 'rev_rate':
        return BOUNDS['rev']
    if 'speed' in metric:
        return BOUNDS['speed']
    return None


def parse_gate(path):
    """clip -> {metrics_detailed, stage_report, diag, basis, reason_code}."""
    out = {}
    for line in open(path, errors='replace'):
        i = line.find('ONDEV_GATE_ROW ')
        if i < 0:
            continue
        try:
            row = json.loads(line[i + len('ONDEV_GATE_ROW '):].strip())
        except json.JSONDecodeError:
            continue
        out[row.get('clip', '?') + '.mov'] = row
    return out


def main():
    if len(sys.argv) < 2:
        raise SystemExit('usage: parity_report.py <gate_output.txt>')
    manifest = json.load(open(MANIFEST))
    gate = parse_gate(sys.argv[1])
    verdicts = {'MATCH': 0, 'UNAVAIL+why': 0, 'NO-REASON': 0, 'DISAGREE': 0, 'IMPLAUSIBLE': 0}
    implausible_hits, disagree_hits, noreason_hits, missing_gate = [], [], [], []
    print(f'{"clip":14} {"metric":22} {"server":>10} {"iphone":>10} {"iph_status":16} verdict')
    print('-' * 92)
    for fn, info in sorted(manifest.items()):
        short = fn[:-4]
        g = gate.get(fn)
        if g is None:
            missing_gate.append(fn)
            continue
        det = g.get('metrics_detailed') or {}
        fstage = (g.get('diag') or {}).get('first_failing_stage')
        server = info.get('server') or {}
        srv_measured = {k: v for k, v in server.items()
                        if v.get('status') in ('measured', 'best_effort', 'calibrated_estimate') and v.get('value') is not None}
        if not srv_measured:
            print(f'{short:14} {"(server measured nothing)":22} {"":>10} {"":>10} {"fail_stage="+str(fstage):16}')
            continue
        for metric, sv in sorted(srv_measured.items()):
            cell = det.get(metric) or {}
            iv, ist, irc = cell.get('value'), cell.get('status'), cell.get('reason_code')
            band = _band(metric)
            if iv is not None and band and not (band[0] <= iv <= band[1]):
                verdict = 'IMPLAUSIBLE'; implausible_hits.append((short, metric, iv))
            elif iv is None or ist == 'unavailable':
                if irc:
                    verdict = 'UNAVAIL+why'
                else:
                    verdict = 'NO-REASON'; noreason_hits.append((short, metric))
            else:
                tol = TOL.get(metric, 2.0)
                if abs(iv - sv['value']) <= tol:
                    verdict = 'MATCH'
                else:
                    verdict = 'DISAGREE'; disagree_hits.append((short, metric, sv['value'], iv))
            verdicts[verdict] += 1
            sstr = f'{sv["value"]:.1f}' if isinstance(sv['value'], (int, float)) else str(sv['value'])
            istr = f'{iv:.1f}' if isinstance(iv, (int, float)) else '—'
            print(f'{short:14} {metric:22} {sstr:>10} {istr:>10} {str(ist or "—")+("/"+irc if irc else ""):16} {verdict}')
    print('-' * 92)
    print('SUMMARY', verdicts)
    print(f'clips in manifest={len(manifest)}  with gate rows={len(manifest)-len(missing_gate)}  missing gate={missing_gate}')
    if implausible_hits:
        print('IMPLAUSIBLE (must be zero):', implausible_hits)
    if noreason_hits:
        print('UNAVAILABLE WITHOUT REASON (item-2 gaps):', noreason_hits)
    if disagree_hits:
        print('DISAGREEMENTS (server vs iphone, out of tol):', disagree_hits)
    ok = not implausible_hits and not noreason_hits
    print('GATE:', 'PASS' if ok else 'FAIL', '— zero implausible + every server-measured metric is matched or unavailable-with-reason'
          if ok else '— see hits above')


if __name__ == '__main__':
    main()
