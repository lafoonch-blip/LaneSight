"""Ten-pin game model and scoring. A roll records pins knocked down and (optionally) the pins left standing,
so leaves, splits and conversions come for free whenever pin reading or a scoring feed supplies them."""
from __future__ import annotations
from dataclasses import dataclass, field
from .pins import ALL_PINS, classify_leave, is_split, leave_key

@dataclass
class Roll:
    pins: int                                  # pins knocked down by this roll
    standing_after: frozenset | None = None    # pins still standing after this roll (None = unknown)
    foul: bool = False
    shot_id: str | None = None                 # link to the analyzed Shot (metrics) when available

@dataclass
class Frame:
    number: int
    rolls: list[Roll] = field(default_factory=list)
    score: int | None = None                   # cumulative score through this frame

    @property
    def is_strike(self): return bool(self.rolls) and self.rolls[0].pins == 10
    @property
    def is_spare(self): return len(self.rolls) >= 2 and not self.is_strike and self.rolls[0].pins + self.rolls[1].pins == 10
    @property
    def is_open(self):
        return len(self.rolls) >= 2 and self.rolls[0].pins < 10 and self.rolls[0].pins + self.rolls[1].pins < 10
    @property
    def first_leave(self):
        if not self.rolls or self.is_strike: return frozenset()
        r = self.rolls[0]
        return r.standing_after if r.standing_after is not None else None
    @property
    def is_split(self):
        lv = self.first_leave
        return bool(lv) and is_split(lv)

class GameError(ValueError): pass

def build_frames(rolls: list[Roll]) -> list[Frame]:
    frames, i = [], 0
    for n in range(1, 11):
        f = Frame(n)
        if i >= len(rolls): frames.append(f); continue
        if n < 10:
            f.rolls.append(rolls[i]); i += 1
            if f.rolls[0].pins > 10: raise GameError(f'frame {n}: more than 10 pins')
            if f.rolls[0].pins < 10 and i < len(rolls):
                f.rolls.append(rolls[i]); i += 1
                if f.rolls[0].pins + f.rolls[1].pins > 10: raise GameError(f'frame {n}: more than 10 pins')
        else:
            while i < len(rolls) and len(f.rolls) < 3:
                f.rolls.append(rolls[i]); i += 1
                p = [r.pins for r in f.rolls]
                if len(p) == 2 and p[0] < 10 and p[0] + p[1] < 10: break
            p = [r.pins for r in f.rolls]
            if len(p) >= 2 and p[0] < 10 and p[0] + p[1] > 10: raise GameError('frame 10: more than 10 pins')
            if len(p) == 3 and p[0] == 10 and p[1] < 10 and p[1] + p[2] > 10: raise GameError('frame 10: more than 10 pins')
        frames.append(f)
    if i < len(rolls): raise GameError('too many rolls')
    _fill_leaves(frames)
    _score(frames)
    return frames

def _fill_leaves(frames):
    """infer standing sets where only counts are known: a strike or spare leaves nothing standing"""
    for f in frames:
        for k, r in enumerate(f.rolls):
            if r.standing_after is None and (r.pins == 10 or (k == 1 and f.rolls[0].pins + r.pins == 10 and f.rolls[0].pins < 10)):
                r.standing_after = frozenset()

def _score(frames):
    flat = [r.pins for f in frames for r in f.rolls]
    total, idx = 0, 0
    for f in frames:
        if not f.rolls: break
        if f.number < 10:
            if f.is_strike:
                if idx + 2 >= len(flat): break
                total += 10 + flat[idx + 1] + flat[idx + 2]; idx += 1
            elif len(f.rolls) == 2:
                if f.is_spare:
                    if idx + 2 >= len(flat): break
                    total += 10 + flat[idx + 2]
                else: total += f.rolls[0].pins + f.rolls[1].pins
                idx += 2
            else: break
        else:
            p = [r.pins for r in f.rolls]
            complete = (len(p) == 3) or (len(p) == 2 and p[0] + p[1] < 10)
            if not complete: break
            total += sum(p)
        f.score = total

@dataclass
class Game:
    rolls: list[Roll]
    game_id: str | None = None
    session_id: str | None = None
    ball_id: str | None = None
    pattern_id: str | None = None
    lane: int | None = None
    frames: list[Frame] = field(init=False)
    def __post_init__(self): self.frames = build_frames(self.rolls)
    @property
    def score(self):
        done = [f.score for f in self.frames if f.score is not None]
        return done[-1] if done else 0
    @property
    def complete(self): return self.frames[9].score is not None

def game_from_string(s: str, **kw) -> Game:
    """'X 9/ 81 ...' notation: X strike, / spare, - miss, F foul, digits 0-9."""
    rolls, rack_first = [], None
    for ch in s.replace(' ', '').replace('|', ''):
        if ch in 'Xx': p = 10; rack_first = None
        elif ch == '/':
            if rack_first is None: raise GameError("'/' without a first ball")
            p = 10 - rack_first; rack_first = None
        else:
            p = 0 if ch in '-F' else int(ch)
            rack_first = p if rack_first is None else None
        rolls.append(Roll(p, foul=(ch == 'F')))
    return Game(rolls, **kw)
