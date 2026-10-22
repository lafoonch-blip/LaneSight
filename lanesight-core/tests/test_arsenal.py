import json
from lanesight_core.arsenal.catalog import normalize, validate, finish_grit, oil_from_text, parse_scale
from lanesight_core.arsenal.recommend import Condition, target_for, rank_for_condition, arsenal_gaps
from lanesight_core.arsenal import build_seed

BASE = dict(manufacturer='Test', name='Ball', product_url='https://x.test/b', spec_source_urls=['https://x.test/b'])


def rec(**kw):
    r = dict(BASE); r.update(kw); return r


def test_retailer_rating_used_only_inside_its_stated_scale():
    rr = {'hook_potential': 200, 'hook_potential_scale': '10-250', 'length': 100, 'length_scale': '25-235'}
    r = normalize(rec(cover_type='solid', retailer_ratings=rr, mfr_ratings={'hook': 'Low', 'length': 'Long'}))
    assert r.ls_hook == round(1 + 9 * 190 / 240, 1) and r.reaction_basis['hook'] == 'retailer_rating'
    assert r.ls_length == round(1 + 9 * (100 - 25) / 210, 1)
    assert r.reaction_confidence == 'high'
    off = normalize(rec(cover_type='solid', retailer_ratings={'hook_potential': 325, 'hook_potential_scale': '10-250'}))
    none = normalize(rec(cover_type='solid', retailer_ratings={'hook_potential': 325}))
    assert off.reaction_basis['hook'] == none.reaction_basis['hook'] == 'spec_estimate'


def test_motion_chart_beats_retailer_number():
    r = normalize(rec(cover_type='pearl', motion_chart={'oil': 9, 'shape': 12},
                      retailer_ratings={'hook_potential': 120, 'hook_potential_scale': '10-250'}))
    assert r.reaction_basis['hook'] == 'mfr_motion_chart' and r.ls_hook == round(1 + 9 * 8 / 15, 1)


def test_longer_retail_length_is_longer():
    sc = {'hook_potential': 200, 'hook_potential_scale': '10-250', 'length_scale': '25-235'}
    early = normalize(rec(cover_type='solid', retailer_ratings={**sc, 'length': 100}))
    late = normalize(rec(cover_type='pearl', retailer_ratings={**sc, 'length': 180}))
    assert late.ls_length > early.ls_length


def test_mfr_numeric_scale_then_labels():
    r = normalize(rec(cover_type='pearl', mfr_ratings={'hook': 150, 'hook_scale': '1-300', 'length': 'Late'}))
    assert r.reaction_basis == {**r.reaction_basis, 'hook': 'mfr_rating', 'length': 'label'}
    assert 5.0 <= r.ls_hook <= 5.6 and r.ls_length == 8.0 and r.reaction_confidence == 'medium'


def test_spec_estimate_is_low_confidence_and_ordered_sensibly():
    strong = normalize(rec(cover_type='solid', core_type='asymmetric', rg_15=2.47, diff_15=0.055,
                           factory_finish='500 SiaAir'))
    weak = normalize(rec(cover_type='urethane', rg_15=2.56, diff_15=0.015, factory_finish='2000 Abralon'))
    poly = normalize(rec(cover_type='polyester', rg_15=2.60, diff_15=0.010, factory_finish='Polished'))
    assert strong.reaction_confidence == weak.reaction_confidence == 'low'
    assert strong.ls_hook > weak.ls_hook > poly.ls_hook
    assert poly.reaction_shape == 'straight' and poly.ls_length > strong.ls_length


def test_nothing_published_and_no_cover_gives_none_not_default():
    r = normalize(rec())
    assert r.ls_hook is None and r.ls_length is None and r.ls_backend is None and r.ls_oil is None


def test_helpers():
    assert finish_grit('500/1500 SiaAir') == 1500
    assert finish_grit('1500 Polished') == 4000
    assert finish_grit(None) is None
    assert oil_from_text('Medium-Heavy Oil') == 'medium_heavy'
    assert oil_from_text('Light to medium') == 'light'
    assert oil_from_text('Heavy') == 'heavy'
    assert parse_scale('scale: 25-235') == (25.0, 235.0) and parse_scale('High') is None


def test_shape_from_published_words():
    r = normalize(rec(cover_type='pearl', mfr_ratings={'reaction_shape': 'Skid/Flip'}))
    assert r.reaction_shape == 'skid_flip' and r.reaction_basis['shape'] == 'mfr_rating'


def test_validate_rejects_bad_values_not_missing_optionals():
    assert validate(rec(cover_type='pearl')) == []
    errs = validate(rec(cover_type='plastic', rg_15=3.1, image_url='http://x'))
    assert any('cover_type' in e for e in errs) and any('rg_15' in e for e in errs) and any('image_url' in e for e in errs)
    assert 'missing product_url' in validate({'manufacturer': 'a', 'name': 'b', 'cover_type': 'solid'})


def test_build_seed_rejects_and_dedupes(tmp_path):
    raw = tmp_path / 'raw'; raw.mkdir()
    good = rec(name='A', cover_type='solid', rg_15='2.48', diff_15=0.05, retailer_ratings={'hook_potential': 200, 'length': 120})
    (raw / 'x.json').write_text(json.dumps([good, good, rec(name='B', cover_type='nope')]))
    rows, problems = build_seed.build(raw)
    assert len(rows) == 1 and rows[0]['rg_15'] == 2.48 and rows[0]['ls_hook'] is not None
    assert len(problems) == 2
    sql = build_seed.to_sql(rows, '2026-10-21')
    assert sql.count('insert into ball_models') == 1 and 'on conflict (manufacturer, name)' in sql
    assert "'::jsonb" in sql


def test_targets_move_the_right_way():
    base = target_for(Condition(oil_level='medium'))
    assert 'assuming' not in ' '.join(base.reasons)
    heavy = target_for(Condition(volume_ml=30))
    high_rev = target_for(Condition(oil_level='medium', rev_rate_rpm=500))
    fast = target_for(Condition(oil_level='medium', speed_mph=19.5))
    long_pat = target_for(Condition(oil_level='medium', pattern_length_ft=47))
    assert heavy.hook > base.hook and high_rev.hook < base.hook
    assert fast.hook > base.hook and fast.length < base.length
    assert long_pat.length < base.length
    assert 'assuming' in ' '.join(target_for(Condition()).reasons)


def test_rank_and_gaps():
    cat = [
        dict(manufacturer='M', name='Heavy', ls_hook=9.0, ls_length=4.0, ls_backend=5, ls_oil='heavy', cover_type='solid'),
        dict(manufacturer='M', name='Bench', ls_hook=5.5, ls_length=5.5, ls_backend=5, ls_oil='medium', cover_type='hybrid'),
        dict(manufacturer='M', name='Dry', ls_hook=3.0, ls_length=8.0, ls_backend=8, ls_oil='light', cover_type='pearl'),
        dict(manufacturer='M', name='Spare', ls_hook=1.0, ls_length=10, ls_backend=1, ls_oil='dry', cover_type='polyester'),
        dict(manufacturer='M', name='NoData', cover_type='solid'),
    ]
    out = rank_for_condition(cat, Condition(oil_level='medium', pattern_length_ft=40))
    assert out['results'][0]['name'] == 'Bench' and out['status'] == 'best_effort'
    assert all(r['name'] != 'NoData' for r in out['results'])
    gaps = arsenal_gaps([cat[1]], cat)
    names = [g['name'] for g in gaps['results']]
    assert 'Bench' not in names and 'Spare' not in names and set(names) == {'Heavy', 'Dry'}


def test_ranged_and_storm_chart_labels():
    from lanesight_core.arsenal.catalog import _label, HOOK_LABELS, LENGTH_LABELS
    assert _label('Medium to High', HOOK_LABELS) == 6.5
    assert _label('Medium-High', HOOK_LABELS) == 6.5
    assert _label('Early-Mid-Lane / Mid-lane', LENGTH_LABELS) == round((4.0 + 5.5) / 2, 1)
    assert _label('Mid-lane-Late / Late', LENGTH_LABELS) == round((7.0 + 8.0) / 2, 1)
    assert _label('Mid to Late', LENGTH_LABELS) == round((5.5 + 8.0) / 2, 1)
    assert _label('Early', LENGTH_LABELS) < _label('Mid-lane', LENGTH_LABELS) < _label('Late', LENGTH_LABELS)
    assert _label('banana', HOOK_LABELS) is None


def test_motion_chart_lifted_from_notes_and_used():
    note = ('Brunswick Ball Motion Comparison Chart (Oct-Nov 2026) plots this ball at oil 10 (scale 1 light oil-16 heavy oil) '
            'x shape 10 (scale 1 smooth-18 angular); bowling.com lists FCC Rating: Total-28.25, Finish-9, Core-7.25, Cover-12')
    r = build_seed.lift_note_ratings(rec(cover_type='solid', notes=note))
    assert r['motion_chart']['oil'] == 10 and r['motion_chart']['shape'] == 10
    assert r['retailer_ratings']['fcc']['total'] == 28.25
    n = normalize(r)
    assert n.reaction_basis['hook'] == 'mfr_motion_chart' and n.ls_hook == round(1 + 9 * 9 / 15, 1)
    assert n.reaction_basis['backend'] == 'mfr_motion_chart'


def test_oil_ranges_and_range_ratings():
    from lanesight_core.arsenal.catalog import oil_range, _rating_num
    assert oil_range('Medium, Medium-Heavy') == ('medium', 'medium', 'medium_heavy')
    assert oil_range('Medium/Heavy Oil') == ('medium_heavy',) * 3
    assert oil_range('Light-Medium / Medium') == ('light', 'medium', 'medium')
    assert oil_range('Any') is None and oil_range(None) is None
    assert _rating_num('3-4') == 3.5 and _rating_num(6) == 6.0 and _rating_num('High') is None
    r = normalize(rec(cover_type='pearl', recommended_oil='Light to Medium Oil',
                      mfr_ratings={'length': '9-10', 'length_scale': '1-11 (1=Early, 11=Late)'}))
    assert r.ls_oil_min == 'light' and r.ls_oil_max == 'medium' and r.ls_length == round(1 + 9 * 8.5 / 10, 1)


def test_colorways_share_published_ratings(tmp_path):
    raw = tmp_path / 'raw'; raw.mkdir()
    same = dict(coverstock_name='C', core_name='K', factory_finish='3000', rg_15=2.5, diff_15=0.03, cover_type='pearl')
    a = rec(name='Surge Red', mfr_ratings={'length': 10, 'length_scale': '1-11'}, recommended_oil='Light', **same)
    b = rec(name='Surge Blue', **same)
    (raw / 'x.json').write_text(json.dumps([a, b]))
    rows, _ = build_seed.build(raw)
    blue = next(r for r in rows if r['name'] == 'Surge Blue')
    assert blue['mfr_ratings']['from_colorway'] == 'Surge Red' and blue['reaction_basis']['length'] == 'mfr_rating'
    assert blue['ls_oil'] == 'light' and 'shared from colorway' in blue['notes']


def test_oil_range_means_no_penalty_inside():
    ball = dict(manufacturer='M', name='R', ls_hook=6.0, ls_length=5.5, ls_oil='medium', ls_oil_min='medium', ls_oil_max='heavy')
    out = rank_for_condition([ball], Condition(oil_level='heavy', pattern_length_ft=40))
    assert not any('built for' in n for n in out['results'][0]['notes'])
