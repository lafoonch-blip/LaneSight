"""Pin geometry and leave classification (USBC numbering; boards counted from the right gutter)."""
from __future__ import annotations

ALL_PINS = frozenset(range(1, 11))
# pins that touch / sit immediately ahead of each other; a leave is a split when the headpin is down and the
# standing pins form two or more groups with a downed pin between them
ADJ = {(1, 2), (1, 3), (2, 3), (2, 4), (2, 5), (3, 5), (3, 6), (4, 5), (5, 6), (4, 7), (4, 8), (5, 8), (5, 9),
       (6, 9), (6, 10), (7, 8), (8, 9), (9, 10)}
NEIGH = {p: set() for p in ALL_PINS}
for a, b in ADJ:
    NEIGH[a].add(b); NEIGH[b].add(a)
# board of each pin's centre (board 1 = right gutter, board 20 = centre) and row
PIN_BOARD = {1: 20, 2: 22.8, 3: 17.2, 4: 25.6, 5: 20, 6: 14.4, 7: 28.5, 8: 22.8, 9: 17.2, 10: 11.5}
PIN_ROW = {1: 1, 2: 2, 3: 2, 4: 3, 5: 3, 6: 3, 7: 4, 8: 4, 9: 4, 10: 4}
MIRROR = {1: 1, 2: 3, 3: 2, 4: 6, 5: 5, 6: 4, 7: 10, 8: 9, 9: 8, 10: 7}

def leave_key(standing) -> str:
    return '-'.join(str(p) for p in sorted(standing)) if standing else 'X'

def groups(standing) -> list[set]:
    left = set(standing); out = []
    while left:
        stack = [left.pop()]; g = set(stack)
        while stack:
            p = stack.pop()
            for q in NEIGH[p] & left:
                left.discard(q); g.add(q); stack.append(q)
        out.append(g)
    return out

def is_split(standing) -> bool:
    s = set(standing)
    return 1 not in s and len(s) >= 2 and len(groups(s)) >= 2

def classify_leave(standing) -> str:
    s = set(standing)
    if not s: return 'strike'
    if len(s) == 1: return 'single'
    if is_split(s): return 'split'
    return 'multi'

def mirror(standing):
    return {MIRROR[p] for p in standing}
