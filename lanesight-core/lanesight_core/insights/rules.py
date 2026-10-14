"""Deterministic bowling rules (v1). Every output carries reason, evidence, confidence and RULES_VERSION so
recommendations are auditable (UI Spec §8, DEC-005). Boards count from the right gutter (1) to the left (39);
everything is written for a right-hander and mirrored for left-handers."""
RULES_VERSION = 'insights-1.0.0'

POCKET_RH = 17.5          # 1-3 pocket centre board at the pin deck
POCKET_WINDOW = 1.5       # +/- boards counted as a pocket hit
BROOKLYN_RH = 22.5        # 1-2 pocket
GOOD_ENTRY_DEG = (4.0, 7.0)

def mirror_board(b): return None if b is None else 40.0 - b

# what a first-ball leave usually says about the hit (right-hander). Kept to widely taught reads only.
LEAVE_READS_RH = {
    '10': ('weak_or_light', 'Ringing/weak 10 pin: the ball deflected or came in a touch light or flat.'),
    '6-10': ('light', '6-10: ball came in light (right of the pocket).'),
    '3-6-10': ('light', '3-6-10: ball came in light and deflected.'),
    '3-10': ('light', '3-10 baby split: light hit.'),
    '6': ('light', 'Single 6 pin: slightly light or weak through the pins.'),
    '3': ('light', '3 pin: light hit, ball deflected off the 1-3.'),
    '2-4-5': ('light', '2-4-5: ball came in light and deflected across.'),
    '2-4-5-8': ('light', '2-4-5-8 bucket: light hit.'),
    '5': ('weak', 'Single 5 pin: pocket hit with too little energy/angle (weak, flat).'),
    '8': ('slightly_high', 'Stone 8: slightly high, or flat through the pins.'),
    '9': ('slightly_light', '9 pin: slightly light or flat.'),
    '7': ('high', 'Single 7 pin: high hit or flat through the pocket.'),
    '4': ('high', 'Single 4 pin: high hit.'),
    '4-7': ('high', '4-7: high hit.'),
    '4-9': ('high', '4-9: high hit.'),
    '2': ('high', 'Single 2 pin (often behind-the-headpin): high hit, or a pin bounced off the kickback.'),
    '4-6': ('nose', '4-6 split: nose (headpin) hit.'),
    '4-6-7-10': ('nose', 'Big four: nose hit.'),
    '7-10': ('high_or_flat', '7-10: usually a high/nose hit or flat entry.'),
    '8-10': ('high', '8-10 split: high hit.'),
    '5-7': ('light', '5-7 split: light hit with too much deflection.'),
}
