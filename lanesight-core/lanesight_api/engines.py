"""Engine wiring (SCORE_TIERS §5/§6, BENCHMARKS §5/§6). Glues the pure engines in lanesight_core to the
store: after each analyzed shot it recomputes the LaneSight Score over the 90-day window, runs the
achievement engine (idempotent progress + unlocks + one activity + one notification each), and at session
end evaluates tiers. Benchmarks compute personal baselines + findings where the data supports it.

No fabricated data: a metric with no qualified data yields 'not_trackable'/'building', never 0% or a guess.
Achievements never change the score or tier (DEC-039). Weights are never rebalanced.
"""
from __future__ import annotations
import datetime as _dt

from lanesight_core.score import compute as score_compute, tier_for, evaluate_tier
from lanesight_core.achievements import evaluate, update_streak
from lanesight_core.benchmarks import personal_baseline, classify_consistency, prioritize
from lanesight_core.insights.routing import route_recommendation

_TIER_ORDER = ['bronze', 'silver', 'gold', 'platinum', 'onyx']
_MEASURED = ('ok', 'calibrated_estimate')
_THROW_METRICS = ['ball_speed', 'rev_rate', 'entry_board', 'entry_angle', 'arrows_board',
                  'breakpoint_board', 'axis_rotation', 'axis_tilt', 'loft', 'launch_angle']
_FORM_METRICS = ['finish_hold', 'swing_time', 'cadence_ratio', 'drift_boards', 'backswing_height_rel']


# --------------------------------------------------------------------------- metric access
def _measured(rec, metric):
    m = (rec.get('metrics') or {}).get(metric)
    if not m or m.get('value') is None or m.get('status') not in _MEASURED:
        return None
    return m['value']


def _unc(rec, metric):
    m = (rec.get('metrics') or {}).get(metric) or {}
    return m.get('uncertainty') or 0.0


def _weight_lb(store, user_id):
    for b in store.list_arsenal(user_id):
        if b.get('weight_lb'):
            try:
                return float(b['weight_lb'])
            except (TypeError, ValueError):
                pass
    return 15.0


def _to_ts(v):
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return _dt.datetime.fromisoformat(str(v).replace('Z', '+00:00')).timestamp()
    except ValueError:
        return None


# --------------------------------------------------------------------------- score recompute
def recompute_score(store, user_id, session_id=None, trigger='shot'):
    from .store import _new_id
    params = store.score_formula_params()
    records, intents, handed = store.read_shot_records(user_id, window_days=params.get('window_days'))
    snap = score_compute(records, intents=intents, params=params, handed=handed,
                         weight_lb=_weight_lb(store, user_id))
    snap['id'] = _new_id()
    snap['trigger'] = trigger
    snap['session_id'] = session_id
    store.save_snapshot(user_id, snap)
    return snap


# --------------------------------------------------------------------------- achievement context
def _weekly_streak(sessions):
    """Longest run of consecutive ISO weeks that have >= 1 completed session."""
    weeks = set()
    for s in sessions:
        ts = _to_ts(s.get('ended_at'))
        if ts is None:
            continue
        d = _dt.date.fromtimestamp(ts)
        monday = d - _dt.timedelta(days=d.weekday())
        weeks.add(monday.toordinal() // 7)
    if not weeks:
        return 0
    ordered = sorted(weeks)
    best = run = 1
    for i in range(1, len(ordered)):
        run = run + 1 if ordered[i] == ordered[i - 1] + 1 else 1
        best = max(best, run)
    return best


def _aggregate(store, user_id, records, intents, handed, params, snapshot):
    sp = params['s_perf']
    lo, hi = sp['pocket_board_range']
    alo, ahi = sp['entry_angle_range_deg']

    def mirror(b):
        return b if handed == 'R' else (40 - b)

    arrow_window, arrow_qual_ids = [], []
    streak = None
    pocket_window, angle_window, bp_window = [], [], []
    speed_values, rev_values, rev_values_tight = [], [], []
    powerhouse_count, powerhouse_ids = 0, []
    best_speed = best_speed_unc = None
    best_rev = best_rev_unc = None
    finish_hold_count = 0
    swing_time_values = []

    for rec in records:
        sid = rec.get('shot_id')
        intent = intents.get(sid) or {}
        arr = _measured(rec, 'arrows_board')
        if intent.get('arrows_board') is not None:
            if arr is not None:
                q = abs(arr - intent['arrows_board']) <= 1
                arrow_window.append(q)
                if q:
                    arrow_qual_ids.append(sid)
                streak = update_streak(streak, {'qualifies': q, 'is_real_attempt': True, 'analyzable': True})
            else:  # intended but unanalyzable at the arrows -> skip (don't break the streak)
                streak = update_streak(streak, {'qualifies': False, 'is_real_attempt': True, 'analyzable': False})
        eb = _measured(rec, 'entry_board')
        if eb is not None:
            pocket_window.append(lo <= mirror(eb) <= hi)
        ea = _measured(rec, 'entry_angle')
        if ea is not None:
            angle_window.append(alo <= ea <= ahi)
        bp = _measured(rec, 'breakpoint_board')
        if intent.get('breakpoint_board') is not None and bp is not None:
            bp_window.append(abs(bp - intent['breakpoint_board']) <= 2)
        sv = _measured(rec, 'ball_speed')
        if sv is not None:
            speed_values.append(sv)
            u = _unc(rec, 'ball_speed')
            if best_speed is None or sv > best_speed:
                best_speed, best_speed_unc = sv, u
        rv = _measured(rec, 'rev_rate')
        if rv is not None:
            rev_values.append(rv)
            u = _unc(rec, 'rev_rate')
            if u and u <= 20:
                rev_values_tight.append(rv)
            if best_rev is None or rv > best_rev:
                best_rev, best_rev_unc = rv, u
        if sv is not None and rv is not None and sv >= 18 and rv >= 400:
            powerhouse_count += 1
            powerhouse_ids.append(sid)
        fh = _measured(rec, 'finish_hold')
        if fh is not None and fh >= 1.5:
            finish_hold_count += 1
        st = _measured(rec, 'swing_time')
        if st is not None:
            swing_time_values.append(st)

    sessions = store.completed_sessions(user_id)
    profile = store.get_profile(user_id) or {}
    arsenal_n = store.arsenal_count(user_id)
    n_valid = len(records)

    # baseline (for ACH-026..028): first qualified score; current: latest eligible score.
    tstate = store.get_tier_state(user_id) or {}
    baseline_score = tstate.get('first_qualified_score')
    hist = store.score_history(user_id)
    eligible_scores = [h['score'] for h in hist if h.get('eligible') and h.get('score') is not None]
    if snapshot and snapshot.get('eligible') and snapshot.get('score') is not None:
        current_score = snapshot['score']
    else:
        current_score = eligible_scores[-1] if eligible_scores else None
    best_score = tstate.get('best_score')
    best_tier = tier_for(best_score, params) if best_score is not None else None
    best_tier_i = _TIER_ORDER.index(best_tier) if best_tier in _TIER_ORDER else -1

    profile_complete = bool(profile.get('handed')
                            and (profile.get('delivery_style') or profile.get('style'))
                            and arsenal_n >= 1)

    return dict(
        n_valid=n_valid, arsenal_count=arsenal_n, n_completed_sessions=len(sessions),
        weekly_streak=_weekly_streak(sessions), profile_complete=profile_complete,
        first_completed_session=(len(sessions) >= 1 and n_valid >= 1),
        arrow_window=arrow_window, arrow_qual_count=len(arrow_qual_ids), arrow_qual_ids=arrow_qual_ids,
        arrow_streak_live=(streak or {}).get('live', 0), arrow_streak_best=(streak or {}).get('best', 0),
        pocket_window=pocket_window, angle_window=angle_window, bp_window=bp_window,
        speed_values=speed_values, rev_values_tight=rev_values_tight,
        powerhouse_count=powerhouse_count, powerhouse_ids=powerhouse_ids,
        best_speed=best_speed, best_speed_unc=best_speed_unc, best_rev=best_rev, best_rev_unc=best_rev_unc,
        current_score=current_score, baseline_score=baseline_score,
        best_tier=best_tier, best_tier_i=best_tier_i,
        finish_hold_count=finish_hold_count, swing_time_values=swing_time_values,
    )


def _context_for(defn, agg):
    i = defn['id']
    ev = None
    if i == 'ACH-050':
        ctx = {'condition_met': agg['profile_complete']}
    elif i == 'ACH-051':
        ctx = {'condition_met': agg['n_valid'] >= 1}
    elif i == 'ACH-052':
        ctx = {'condition_met': agg['first_completed_session']}
    elif i in ('ACH-053', 'ACH-054'):
        ctx = {'count': agg['n_valid']}
    elif i == 'ACH-055':
        ctx = {'count': agg['arsenal_count']}
    elif i == 'ACH-049':
        ctx = {'count': agg['n_completed_sessions']}
    elif i == 'ACH-048':
        ctx = {'consecutive_weeks': agg['weekly_streak']}
    elif i == 'ACH-010':
        ctx = {'qualifying_count': agg['arrow_qual_count']}; ev = agg['arrow_qual_ids']
    elif i == 'ACH-011':
        ctx = {'window': agg['arrow_window']}
    elif i == 'ACH-013':
        ctx = {'window': agg['pocket_window']}
    elif i == 'ACH-014':
        ctx = {'window': agg['bp_window']}
    elif i == 'ACH-020':
        ctx = {'window': agg['angle_window']}
    elif i == 'ACH-023':
        ctx = {'live': agg['arrow_streak_live'], 'best': agg['arrow_streak_best']}
    elif i == 'ACH-016':
        ctx = {'best_value': agg['best_speed'], 'uncertainty': agg['best_speed_unc']}
    elif i == 'ACH-017':
        ctx = {'best_value': agg['best_rev'], 'uncertainty': agg['best_rev_unc']}
    elif i == 'ACH-018':
        ctx = {'qualifying_count': agg['powerhouse_count']}; ev = agg['powerhouse_ids']
    elif i == 'ACH-021':
        ctx = {'values': agg['speed_values']}
    elif i == 'ACH-022':
        ctx = {'values': agg['rev_values_tight']}
    elif i in ('ACH-026', 'ACH-027', 'ACH-028'):
        ctx = {'current': agg['current_score'], 'baseline': agg['baseline_score']}
    elif i in ('ACH-056', 'ACH-057', 'ACH-058', 'ACH-059'):
        need = {'ACH-056': 1, 'ACH-057': 2, 'ACH-058': 3, 'ACH-059': 4}[i]
        ctx = {'reached': agg['best_tier_i'] >= need, 'tier': agg['best_tier']}
    elif i == 'FORM-001':
        ctx = {'qualifying_count': agg['finish_hold_count']}
    elif i == 'FORM-002':
        ctx = {'values': agg['swing_time_values']}
    else:
        ctx = {}
    return ctx, ev


def run_achievements(store, user_id, trigger='shot', snapshot=None):
    """Evaluate every active achievement, upsert progress, insert unlock + one activity + one notification
    on a first crossing (idempotent via the unique (user, achievement, level) keys)."""
    params = store.score_formula_params()
    records, intents, handed = store.read_shot_records(user_id, window_days=params.get('window_days'))
    agg = _aggregate(store, user_id, records, intents, handed, params, snapshot)
    unlocked, nudges = [], []
    for d in store.achievement_defs(active_only=True):
        ctx, ev = _context_for(d, agg)
        prog = evaluate(d, ctx)
        prog['level'] = 1
        if ev:
            prog['evidence_ref'] = {'shot_ids': ev[:50]}
        store.upsert_ach_progress(user_id, prog)
        if prog.get('unlocked'):
            _unlock, created = store.add_ach_unlock(user_id, d['id'], 1, prog.get('current_value'),
                                                    prog.get('evidence_ref') or {}, d.get('rule_version', 1))
            if created:
                payload = {'achievement_id': d['id'], 'name': d['name'], 'description': d['description'],
                           'category': d['category'], 'value': prog.get('current_value'),
                           'target': prog.get('target_value')}
                ref = f"{d['id']}:1"
                store.add_activity(user_id, 'achievement_unlocked', ref, payload)
                store.add_notification(user_id, 'achievement_popup', ref, d.get('popup_priority', 50), payload)
                unlocked.append(d['id'])
        elif (prog.get('status') == 'in_progress' and prog.get('current_value') is not None
              and prog.get('target_value')):
            nudges.append({'achievement_id': d['id'], 'name': d['name'],
                           'current': prog.get('current_value'), 'target': prog.get('target_value')})
    return {'unlocked': unlocked, 'nudges': nudges}


# --------------------------------------------------------------------------- tiers (session end)
def _distance_to_next(score, params):
    for name in _TIER_ORDER:
        lo, _hi = params['tier_ranges'][name]
        if score < lo:
            return {'next_tier': name, 'points': lo - score}
    return {'next_tier': None, 'points': 0}


def evaluate_tiers(store, user_id, snapshot):
    """Session-end tier evaluation (DEC-051). Writes tier_state + tier_event, a celebration on first-time,
    a banner on regain, a quiet activity line on demotion. Never during recording; tier > achievement."""
    params = store.score_formula_params()
    prev = store.get_tier_state(user_id)
    res = evaluate_tier(prev, snapshot, params)
    state = dict(res['state'])
    if res['personal_best'] and snapshot.get('score') is not None:
        state['best_score_at'] = _dt.datetime.now(_dt.timezone.utc).isoformat()
        store.add_activity(user_id, 'personal_best', f"pb:{snapshot['score']}", {'score': snapshot['score']})
    store.save_tier_state(user_id, state)
    ev = res['event']
    if ev:
        tev = store.add_tier_event(user_id, {'from_tier': ev['from_tier'], 'to_tier': ev['to_tier'],
                                             'kind': ev['kind'], 'first_time': ev['first_time'],
                                             'score': ev['score'], 'snapshot_id': snapshot.get('id')})
        dist = _distance_to_next(ev['score'], params)
        if ev['kind'] == 'promotion':
            if ev['first_time']:
                store.add_activity(user_id, 'tier_promotion', f"{ev['to_tier']}:first", {**ev, **dist})
                store.add_notification(user_id, 'tier_celebration', f"{ev['to_tier']}:first", 100,
                                       {**ev, **dist})
            else:
                rid = f"{ev['to_tier']}:{tev['id']}"
                store.add_activity(user_id, 'tier_promotion', rid, {**ev, **dist})
                store.add_notification(user_id, 'tier_banner', rid, 70, {**ev, **dist})
        else:  # demotion: quiet activity line, no popup
            store.add_activity(user_id, 'tier_demotion', f"{ev['to_tier']}:{tev['id']}", {**ev, **dist})
    return res


# --------------------------------------------------------------------------- benchmarks / findings
def compute_findings(store, user_id, records, session_id=None):
    """Personal baselines for each measured metric + consistency findings where the recent spread exceeds
    the personal band. Findings are only ever raised on Measured metrics (DEC-042)."""
    cfg = store.engine_config()
    min_n = int(cfg.get('baseline_min_n', 10))
    stored = []
    for metric in ['ball_speed', 'rev_rate', 'entry_angle', 'entry_board', 'arrows_board', 'breakpoint_board']:
        vals = [v for v in (_measured(r, metric) for r in records) if v is not None]
        if not vals:
            continue
        base = personal_baseline(vals, min_n=min_n)
        store.upsert_baseline(user_id, metric, base)
        if base['established'] and base.get('sd') and len(vals) >= min_n:
            import numpy as np
            recent = vals[-min_n:]
            spread = float(np.std(recent))
            cc = classify_consistency(spread, base['sd'])
            if cc['status'] in ('watch', 'outside'):
                f = store.add_finding(user_id, {'metric': metric, 'session_id': session_id,
                                                'benchmark_layer': 'personal', 'consistency_status': cc['status'],
                                                'confidence': 0.6})
                stored.append(f)
    return stored


def _form_finding(findings):
    """A stored form finding that explains an execution miss, for routing (none in the shot-only build)."""
    for f in findings or []:
        if f.get('metric') in _FORM_METRICS and f.get('explains_miss'):
            return f
    return None


# --------------------------------------------------------------------------- orchestration
def after_shot_analyzed(store, user_id, session_id, record):
    """Called by the analyze job after a shot result is saved: recompute score, run achievements, compute
    findings, and return the shot-card footer payload (score_delta + achievement_nudges + routing)."""
    prev = store.latest_score(user_id)
    snap = recompute_score(store, user_id, session_id, trigger='shot')
    ach = run_achievements(store, user_id, 'shot', snap)
    records, _intents, _handed = store.read_shot_records(user_id,
                                                         window_days=store.score_formula_params().get('window_days'))
    findings = compute_findings(store, user_id, records, session_id)
    insights = record.get('insights') or {}
    route = route_recommendation(insights.get('classification'), insights.get('recommendations'),
                                 _form_finding(findings))
    delta = None
    if snap.get('score') is not None and prev and prev.get('score') is not None:
        delta = snap['score'] - prev['score']
    return {'eligible': snap['eligible'], 'score': snap['score'], 'score_delta': delta,
            'achievement_nudges': ach['nudges'], 'unlocked': ach['unlocked'], 'recommendation': route}


# --------------------------------------------------------------------------- form engine (form-only)
# Form measurements are best_effort by construction (the rear-view pose method), so a value counts for a
# baseline/finding when it is 'ok' OR 'best_effort' — never when unavailable/low_confidence (slo-mo etc.).
_FORM_MEASURED = ('ok', 'best_effort')
# Numeric form metrics worth a personal baseline (the design's swing-timing + approach/balance tiles).
_FORM_BASELINE_METRICS = ['pushaway_time', 'backswing_time', 'downswing_time', 'release_time', 'swing_time',
                          'approach_time', 'finish_hold', 'rhythm_ratio', 'backswing_height_rel', 'step_count']
# form_rule.trigger.metric -> our measured metric key. Only rules whose metric we can faithfully evaluate are
# mapped; the rest (timing_at_slide / drift_boards / swing_line_offset / phase_splits consistency / cadence
# step-inversion) stay unmapped so FOCUS never fires on a metric we don't actually measure (no fabrication).
_RULE_METRIC_MAP = {'finish_hold': 'finish_hold', 'backswing_height_rel': 'backswing_height_rel'}
# Direction phrasing for a level finding (value below/above the personal band).
_FORM_DIRECTION = {'finish_hold': ('shorter', 'longer'), 'swing_time': ('shorter', 'longer')}


def _form_val(rec, metric):
    m = (rec.get('metrics') or {}).get(metric)
    if not m or m.get('value') is None or m.get('status') not in _FORM_MEASURED:
        return None
    return m['value']


def _fmt(v, unit):
    return f'{v:.1f} {unit}' if unit == 's' else f'{v:.2f}'


def compute_form_baselines(store, user_id, history, current, min_n):
    """Per-metric personal baseline over the user's FORM deliveries (history + this one), stored in
    personal_baseline under view='form' so it never mixes with ball baselines. Returns {metric: base}."""
    all_recs = list(history) + [current]
    bases = {}
    for metric in _FORM_BASELINE_METRICS:
        vals = [v for v in (_form_val(r, metric) for r in all_recs) if v is not None]
        if not vals:
            continue
        base = personal_baseline(vals, min_n=min_n)
        store.upsert_baseline(user_id, metric, base, view='form')
        bases[metric] = base
    return bases


def _attach_baselines_and_watch(record, bases, current):
    """Attach baseline:{median,sd,band,n} + watch:bool to each metric when an established baseline exists;
    baseline=None (honest 'building') otherwise. WATCH = measured value outside the personal band."""
    metrics = record.get('metrics') or {}
    for metric, base in bases.items():
        mm = metrics.get(metric)
        if not mm:
            continue
        if base.get('established'):
            mm['baseline'] = {'established': True, 'median': base['median'], 'sd': base['sd'], 'n': base['n'],
                              'band_low': base['band_low'], 'band_high': base['band_high']}
            val = _form_val(current, metric)
            if val is not None and base['band_low'] is not None and base['band_high'] is not None:
                mm['watch'] = bool(val < base['band_low'] or val > base['band_high'])
        else:
            mm['baseline'] = None       # building — not enough deliveries yet


def _form_focus(store, record, bases, history, current):
    """Evaluate the seeded form_rule rows against the measured metrics + established baselines, prioritize, and
    return focus:{cue, drill, metric, comparison_text, rule_id} for the top trigger (None if nothing fires)."""
    import numpy as np
    metrics = record.get('metrics') or {}
    weights = (store.engine_config() or {}).get('prioritizer_weights') or {}
    # map our metric -> prioritizer weight group
    wmap = {'finish_hold': weights.get('finish', 1.0), 'backswing_height_rel': weights.get('timing', 1.0)}
    all_recs = list(history) + [current]
    findings = []
    for rule in store.form_rules():
        trig = rule.get('trigger') or {}
        key = _RULE_METRIC_MAP.get(trig.get('metric'))
        if key is None:
            continue
        base = bases.get(key)
        if not base or not base.get('established'):
            continue
        mm = metrics.get(key)
        val = _form_val(current, key)
        if mm is None or val is None:
            continue
        unit = mm.get('unit', '')
        comparison = trig.get('comparison')
        rule_txt = str(trig.get('rule', ''))
        text = None
        if comparison == 'level' or '< baseline' in rule_txt or '> baseline' in rule_txt:
            low, high = base['band_low'], base['band_high']
            if low is None or high is None:
                continue
            side = 'low' if val < low else ('high' if val > high else None)
            if side is None:
                continue
            # count the last 5 measured deliveries on the same side (the design's "3 of your last 5")
            recent = [v for v in (_form_val(r, key) for r in all_recs) if v is not None][-5:]
            edge = low if side == 'low' else high
            k = sum(1 for v in recent if (v < low if side == 'low' else v > high))
            lo_word, hi_word = _FORM_DIRECTION.get(key, ('lower', 'higher'))
            word = lo_word if side == 'low' else hi_word
            text = (f'{word} than your baseline on {k} of your last {len(recent)} '
                    f'deliveries ({_fmt(val, unit)} vs {_fmt(base["median"], unit)}).')
            sev = abs(val - edge) / max(high - low, 1e-6)
            findings.append({'metric': key, 'severity': sev, 'confidence': mm.get('confidence', 0.5),
                             'rule_id': rule['id'], 'cue': rule.get('cue'), 'drill_ref': rule.get('drill_ref'),
                             'comparison_text': text})
        elif comparison == 'consistency':
            if not base.get('sd'):
                continue
            recent = [v for v in (_form_val(r, key) for r in all_recs) if v is not None][-min(len(all_recs), 10):]
            if len(recent) < 3:
                continue
            spread = float(np.std(recent))
            cc = classify_consistency(spread, base['sd'])
            if cc['status'] not in ('watch', 'outside'):
                continue
            text = (f'more variable than your baseline on your last {len(recent)} deliveries '
                    f'(spread {_fmt(spread, unit)} vs {_fmt(base["sd"], unit)}).')
            findings.append({'metric': key, 'severity': cc['ratio'], 'confidence': mm.get('confidence', 0.5),
                             'rule_id': rule['id'], 'cue': rule.get('cue'), 'drill_ref': rule.get('drill_ref'),
                             'comparison_text': text})
    if not findings:
        return None
    primary = prioritize(findings, wmap)['primary']
    drills = {d['id']: d for d in store.drills()}
    d = drills.get(primary.get('drill_ref')) or {}
    return {'cue': primary.get('cue'), 'metric': primary['metric'], 'rule_id': primary['rule_id'],
            'comparison_text': primary['comparison_text'],
            'drill': {'id': primary.get('drill_ref'), 'name': d.get('name'), 'how': d.get('description')}}


def after_form_analyzed(store, user_id, session_id, record, analyze_seconds=None):
    """Form-only post-analysis (mirrors after_shot_analyzed but touches NOTHING on the ball L-dev-0 score):
    per-metric form baselines, WATCH flags, the FOCUS insight, and the footer. Mutates `record` in place and
    returns a small footer dict for the job result. Call BEFORE save_shot_result so the current delivery is
    counted once (it is not yet persisted, so read_form_records returns strictly prior deliveries)."""
    cfg = store.engine_config() or {}
    min_n = int(cfg.get('baseline_min_n', 10))
    window_days = store.score_formula_params().get('window_days')
    history = store.read_form_records(user_id, window_days=window_days)
    bases = compute_form_baselines(store, user_id, history, record, min_n)
    _attach_baselines_and_watch(record, bases, record)
    focus = _form_focus(store, record, bases, history, record)
    record['focus'] = focus
    rules_version = max((int(r.get('version', 1) or 1) for r in store.form_rules()), default=1)
    record['footer'] = {
        'analyzed_s': round(float(analyze_seconds), 1) if analyze_seconds is not None else None,
        'form_version': record.get('form_version'),
        'rules_version': rules_version,
    }
    return {'focus': focus, 'key_frames': record.get('key_frames', []),
            'n_form_deliveries': len(history) + 1, 'footer': record['footer']}


def at_session_end(store, user_id, session_id):
    """Session end: a session-end snapshot, tier evaluation (before achievements so first-tier Status can
    see the new tier), then achievements, with extra unlocks batched for the summary."""
    snap = recompute_score(store, user_id, session_id, trigger='session_end')
    tier = evaluate_tiers(store, user_id, snap)
    ach = run_achievements(store, user_id, 'session_end', snap)
    records, _i, _h = store.read_shot_records(user_id,
                                              window_days=store.score_formula_params().get('window_days'))
    compute_findings(store, user_id, records, session_id)
    return snap, tier, ach


# --------------------------------------------------------------------------- stats (GET /me/stats)
def _coverage(records, metrics):
    n = len(records)
    cov, reasons = {}, {}
    for m in metrics:
        have = sum(1 for r in records if _measured(r, m) is not None)
        cov[m] = {'measured': have, 'total': n, 'pct': round(100 * have / n) if n else None}
    for r in records:
        for m in metrics:
            mm = (r.get('metrics') or {}).get(m)
            if mm and mm.get('status') not in _MEASURED:
                reason = mm.get('note') or mm.get('status') or 'unavailable'
                key = (m, reason)
                reasons[key] = reasons.get(key, 0) + 1
    top = sorted(({'metric': k[0], 'reason': k[1], 'count': v} for k, v in reasons.items()),
                 key=lambda x: -x['count'])[:5]
    return cov, top


def user_stats(store, user_id, view='throw', range_=None):
    params = store.score_formula_params()
    days = None
    if range_:
        r = str(range_).lower().strip()
        if r.endswith('d') and r[:-1].isdigit():
            days = int(r[:-1])
        elif r.isdigit():
            days = int(r)
    records, intents, _handed = store.read_shot_records(user_id, window_days=days)
    n = len(records)
    if view == 'score':
        snap = store.latest_score(user_id)
        hist = [{'computed_at': h.get('computed_at'), 'score': h.get('score'), 'tier': h.get('tier'),
                 'eligible': h.get('eligible'), 'trigger': h.get('trigger')}
                for h in store.score_history(user_id) if h.get('trigger') == 'session_end']
        if not snap:
            return {'view': 'score', 'empty': True, 'n_shots': n, 'history': hist}
        return {'view': 'score', 'empty': False, 'n_shots': n,
                'score': snap.get('score'), 'tier': snap.get('tier'), 'eligible': snap.get('eligible'),
                'components': {k: snap.get(k) for k in ('s_perf', 'a_acc', 'c_cons', 'p_power')},
                'eligibility': snap.get('eligibility'), 'history': hist}
    if view == 'form':
        cov, top = _coverage(records, _FORM_METRICS)
        measured_any = any(v['measured'] for v in cov.values())
        return {'view': 'form', 'empty': not measured_any, 'n_shots': n,
                'metric_coverage': cov, 'top_failure_reasons': top,
                'note': 'Form metrics require form clips / supported angles.' if not measured_any else None}
    # default: throw
    cov, top = _coverage(records, _THROW_METRICS)
    import numpy as np
    averages = {}
    for m in _THROW_METRICS:
        vals = [v for v in (_measured(r, m) for r in records) if v is not None]
        averages[m] = {'mean': round(float(np.mean(vals)), 2), 'n': len(vals)} if vals else {'mean': None, 'n': 0}
    return {'view': 'throw', 'empty': n == 0, 'n_shots': n, 'averages': averages,
            'metric_coverage': cov, 'top_failure_reasons': top}
