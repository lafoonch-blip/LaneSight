"""LaneTalk-parity statistics over any set of games (a session, a ball, a pattern, a date range, all-time).
Every rate returns (value, made, attempts) so the UI can show '23 of 31' and confidence."""
from __future__ import annotations
from collections import defaultdict
from dataclasses import dataclass
from .game import Game, Frame
from .pins import classify_leave, leave_key

def _rate(m, a): return (round(100.0 * m / a, 1) if a else None, m, a)

def strike_opportunities(g: Game):
    """(is_strike, frame_no, roll_obj) for every ball thrown at a full rack"""
    out = []
    for f in g.frames:
        if not f.rolls: continue
        if f.number < 10: out.append((f.is_strike, f.number, f.rolls[0]))
        else:
            p = [r.pins for r in f.rolls]
            out.append((p[0] == 10, 10, f.rolls[0]))
            if len(p) >= 2 and p[0] == 10: out.append((p[1] == 10, 10, f.rolls[1]))
            if len(p) == 3 and ((p[0] == 10 and p[1] == 10) or (p[0] < 10 and p[0] + p[1] == 10)):
                out.append((p[2] == 10, 10, f.rolls[2]))
    return out

def spare_attempts(g: Game):
    """(converted, leave_set_or_None, first_roll, second_roll) for every ball thrown at a leave"""
    out = []
    for f in g.frames:
        p = [r.pins for r in f.rolls]
        if f.number < 10:
            if len(p) == 2 and p[0] < 10: out.append((p[0] + p[1] == 10, f.rolls[0].standing_after, f.rolls[0], f.rolls[1]))
        else:
            if len(p) >= 2 and p[0] < 10: out.append((p[0] + p[1] == 10, f.rolls[0].standing_after, f.rolls[0], f.rolls[1]))
            if len(p) == 3 and p[0] == 10 and p[1] < 10: out.append((p[1] + p[2] == 10, f.rolls[1].standing_after, f.rolls[1], f.rolls[2]))
    return out

def strings(g: Game):
    """lengths of consecutive-strike runs across the game (strike opportunities in order)"""
    runs, cur = [], 0
    for s, _, _ in strike_opportunities(g):
        if s: cur += 1
        else:
            if cur: runs.append(cur)
            cur = 0
    if cur: runs.append(cur)
    return runs

def game_stats(games: list[Game], shots_by_id: dict | None = None, handed: str = 'R',
               pocket=(16.0, 19.5)) -> dict:
    games = [g for g in games if g.complete] or games
    so = [x for g in games for x in strike_opportunities(g)]
    sa = [x for g in games for x in spare_attempts(g)]
    st = {}
    st['games'] = len(games)
    scores = [g.score for g in games]
    st['average'] = round(sum(scores) / len(scores), 1) if scores else None
    st['high_game'] = max(scores) if scores else None
    st['low_game'] = min(scores) if scores else None
    if len(scores) >= 3: st['high_series_3'] = max(sum(scores[i:i + 3]) for i in range(len(scores) - 2))
    st['strike_pct'] = _rate(sum(s for s, _, _ in so), len(so))
    st['spare_pct'] = _rate(sum(c for c, *_ in sa), len(sa))
    known = [(c, lv) for c, lv, *_ in sa if lv is not None]
    single = [c for c, lv in known if classify_leave(lv) == 'single']
    multi = [c for c, lv in known if classify_leave(lv) == 'multi']
    split = [c for c, lv in known if classify_leave(lv) == 'split']
    st['single_pin_spare_pct'] = _rate(sum(single), len(single))
    st['multi_pin_spare_pct'] = _rate(sum(multi), len(multi))
    st['split_conversion_pct'] = _rate(sum(split), len(split))
    st['splits_left'] = len(split)
    nonsplit = [c for c, lv in known if classify_leave(lv) != 'split']
    st['makeable_spare_pct'] = _rate(sum(nonsplit), len(nonsplit))
    frames = [f for g in games for f in g.frames if f.rolls]
    opens = [f for f in frames if f.is_open]
    st['open_frames'] = len(opens); st['open_frames_per_game'] = round(len(opens) / max(1, len(games)), 2)
    st['clean_games'] = sum(1 for g in games if not any(f.is_open for f in g.frames))
    st['first_ball_avg'] = round(sum(r.pins for _, _, r in so) / len(so), 2) if so else None
    st['fill_avg'] = round(sum(r2.pins for _, _, _, r2 in sa) / len(sa), 2) if sa else None
    runs = [r for g in games for r in strings(g)]
    st['doubles'] = sum(1 for r in runs if r >= 2); st['turkeys'] = sum(1 for r in runs if r >= 3)
    st['longest_string'] = max(runs) if runs else 0
    st['strikes_per_game'] = round(sum(s for s, _, _ in so) / max(1, len(games)), 2)
    st['tenth_frame_strike_pct'] = _rate(sum(s for s, n, _ in so if n == 10), sum(1 for _, n, _ in so if n == 10))
    # per-leave and per-pin conversion
    by_leave = defaultdict(lambda: [0, 0]); by_pin = defaultdict(lambda: [0, 0])
    for c, lv in known:
        k = leave_key(lv); by_leave[k][0] += c; by_leave[k][1] += 1
        if len(lv) == 1: p = next(iter(lv)); by_pin[p][0] += c; by_pin[p][1] += 1
    st['leaves'] = {k: dict(made=m, attempts=a, pct=_rate(m, a)[0], type=classify_leave(set(map(int, k.split('-')))))
                    for k, (m, a) in sorted(by_leave.items(), key=lambda kv: -kv[1][1])}
    st['single_pin_conversion'] = {p: dict(made=m, attempts=a, pct=_rate(m, a)[0]) for p, (m, a) in sorted(by_pin.items())}
    # pocket / carry (needs shot metrics linked through Roll.shot_id)
    if shots_by_id:
        ph = [(s, r) for s, _, r in so if r.shot_id in shots_by_id and shots_by_id[r.shot_id].get('entry_board') is not None]
        inp = [(s, r) for s, r in ph if pocket[0] <= shots_by_id[r.shot_id]['entry_board'] <= pocket[1]]
        st['pocket_pct'] = _rate(len(inp), len(ph))
        st['carry_pct'] = _rate(sum(s for s, _ in inp), len(inp))
        st['strikes_off_pocket'] = sum(s for s, r in ph if not pocket[0] <= shots_by_id[r.shot_id]['entry_board'] <= pocket[1])
    return st

def trend(values: list[float], window: int = 5) -> list[float | None]:
    out = []
    for i in range(len(values)):
        w = [v for v in values[max(0, i - window + 1):i + 1] if v is not None]
        out.append(round(sum(w) / len(w), 2) if w else None)
    return out

def group_stats(games: list[Game], key: str, **kw) -> dict:
    """stats split by any Game attribute: 'session_id', 'ball_id', 'pattern_id', 'lane'"""
    g = defaultdict(list)
    for x in games: g[getattr(x, key)].append(x)
    return {k: game_stats(v, **kw) for k, v in g.items()}
