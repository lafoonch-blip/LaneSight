from lanesight_core.scoring.game import Game, Roll, game_from_string, GameError
from lanesight_core.scoring.pins import is_split, classify_leave, leave_key
from lanesight_core.scoring.stats import game_stats
import pytest

def test_perfect_game():
    assert game_from_string('XXXXXXXXXXXX').score == 300

def test_all_spares_and_nines():
    assert game_from_string('9/' * 10 + '9').score == 190
    assert game_from_string('9-' * 10).score == 90

def test_mixed_game():
    g = game_from_string('X 7/ 9- X -8 8/ -6 X X X81')
    assert g.score == 167
    assert [f.score for f in g.frames] == [20, 39, 48, 66, 74, 84, 90, 120, 148, 167]

def test_incomplete_game_scores_known_frames():
    g = game_from_string('X X 9')
    assert g.frames[0].score == 29 and g.frames[1].score is None and not g.complete

def test_invalid_counts():
    with pytest.raises(GameError): Game([Roll(7), Roll(5)])

def test_splits():
    for lv in ({7, 10}, {4, 6}, {2, 7}, {3, 10}, {5, 7}, {8, 10}, {4, 6, 7, 10}):
        assert is_split(lv), lv
    for lv in ({9, 10}, {3, 6, 10}, {1, 2, 10}, {2, 4, 5, 8}, {10}, {6, 10}):
        assert not is_split(lv), lv
    assert classify_leave({10}) == 'single' and classify_leave({3, 6, 10}) == 'multi' and classify_leave(set()) == 'strike'
    assert leave_key({10, 3, 6}) == '3-6-10'

def test_stats_with_leaves():
    rolls = [Roll(10), Roll(9, frozenset({10})), Roll(1), Roll(8, frozenset({7, 10})), Roll(0),
             Roll(10), Roll(10), Roll(7, frozenset({3, 6, 10})), Roll(3), Roll(9, frozenset({10})), Roll(0),
             Roll(10), Roll(10), Roll(9, frozenset({7})), Roll(1), Roll(10)]
    g = Game(rolls)
    assert g.complete
    st = game_stats([g])
    assert st['strike_pct'][1:] == (6, 11)
    assert st['spare_pct'][1:] == (3, 5)
    assert st['split_conversion_pct'][1:] == (0, 1)
    assert st['single_pin_conversion'][10] == dict(made=1, attempts=2, pct=50.0)
    assert st['leaves']['3-6-10']['made'] == 1
    assert st['open_frames'] == 2 and st['clean_games'] == 0
    assert st['doubles'] == 2 and st['longest_string'] == 2

def test_pocket_and_carry():
    rolls = [Roll(10, shot_id='a'), Roll(9, frozenset({10}), shot_id='b'), Roll(1)] + [Roll(0)] * 16
    g = Game(rolls)
    shots = {'a': {'entry_board': 17.5}, 'b': {'entry_board': 18.0}}
    st = game_stats([g], shots_by_id=shots)
    assert st['pocket_pct'][1:] == (2, 2) and st['carry_pct'][1:] == (1, 2)
