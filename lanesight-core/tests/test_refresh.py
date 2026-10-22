import json
import pytest
from lanesight_core.arsenal import build_seed
from lanesight_core.arsenal.refresh import (merge_brand, summarize, summary_markdown, rows_to_sync, sync_chunks,
                                            RefreshError, main)


def ball(name, **kw):
    r = dict(manufacturer='Storm', name=name, cover_type='pearl', product_url='https://x.test/' + name,
             spec_source_urls=['https://x.test/' + name], rg_15=2.50, diff_15=0.040, factory_finish='1500 Polished')
    r.update(kw)
    return r


def lineup(*names):
    return [ball(n) for n in names]


def test_merge_adds_updates_retires_and_revives():
    old = lineup('A', 'B', 'C', 'D') + [ball('Z', status='discontinued', discontinued_on='2026-01-01')]
    fresh = [ball('A'), ball('B', rg_15=2.51), ball('C'), ball('D'), ball('E'), ball('Z')]
    merged, rep = merge_brand(old, fresh, '2026-10-26')
    assert rep['added'] == ['E'] and rep['updated'] == ['B'] and rep['revived'] == ['Z'] and rep['retired'] == []
    by = {r['name']: r for r in merged}
    assert by['Z']['status'] == 'current' and 'discontinued_on' not in by['Z']

    merged2, rep2 = merge_brand(merged, [ball(n) for n in 'ABCDZ'], '2026-11-02')
    by2 = {r['name']: r for r in merged2}
    assert rep2['retired'] == ['E'] and by2['E']['status'] == 'discontinued' and by2['E']['discontinued_on'] == '2026-11-02'
    assert len(merged2) == 6                                   # nothing deleted


def test_merge_refuses_broken_collections():
    old = lineup(*'ABCDEFGHIJ')
    with pytest.raises(RefreshError, match='empty'):
        merge_brand(old, [], '2026-10-26')
    with pytest.raises(RefreshError, match='broken collection'):
        merge_brand(old, lineup('A', 'B', 'C'), '2026-10-26')            # would retire 7 of 10
    merged, rep = merge_brand(old, lineup('A', 'B', 'C'), '2026-10-26', force=True)
    assert len(rep['retired']) == 7
    with pytest.raises(RefreshError, match='validation'):
        merge_brand(old, old + [ball('Bad', cover_type='plastic')], '2026-10-26')
    with pytest.raises(RefreshError, match='duplicate'):
        merge_brand(old, old + [ball('A')], '2026-10-26')


def _build(tmp_path, recs, name='x'):
    raw = tmp_path / name
    raw.mkdir()
    (raw / 'storm.json').write_text(json.dumps(recs))
    rows, problems = build_seed.build(raw)
    assert problems == []
    return rows


def test_hash_stable_and_sync_only_changed(tmp_path):
    rows1 = _build(tmp_path, lineup('A', 'B', 'C'), 'one')
    rows2 = _build(tmp_path, [ball('A'), ball('B', rg_15=2.52), ball('C', status='discontinued', discontinued_on='2026-10-26'),
                              ball('D')], 'two')
    h1 = {f"{r['manufacturer']}|{r['name']}": r['source_hash'] for r in rows1}
    assert {r['name'] for r in rows_to_sync(rows1, h1)} == set()
    assert {r['name'] for r in rows_to_sync(rows2, h1)} == {'B', 'C', 'D'}
    # retrieval date doesn't change the hash
    assert build_seed.row_hash(rows1[0]) == rows1[0]['source_hash']
    sql = ''.join(sync_chunks(rows_to_sync(rows2, h1), '2026-10-26'))
    assert sql.count('insert into ball_models') == 3
    assert not any(l.strip().lower().startswith('delete') for l in sql.splitlines())
    assert "'discontinued'" in sql and "'2026-10-26'" in sql


def test_sync_chunks_respect_size():
    rows = [dict(ball(f'N{i}'), status='current', source_hash='h') for i in range(30)]
    chunks = sync_chunks(rows, '2026-10-26', max_bytes=6000)
    assert len(chunks) > 1 and all(len(c.encode()) <= 6000 or c.count('insert') == 1 for c in chunks)
    assert sum(c.count('insert into ball_models') for c in chunks) == 30
    assert all(c.startswith('-- Generated') and c.rstrip().endswith('commit;') for c in chunks)


def test_summarize_and_markdown(tmp_path):
    old = _build(tmp_path, lineup('A', 'B', 'C'), 'o')
    new = _build(tmp_path, [ball('A'), ball('B', rg_15=2.52), ball('C', status='discontinued', discontinued_on='2026-10-26'),
                            ball('D')], 'n')
    s = summarize(old, new)
    assert s['added'] == ['Storm D'] and s['retired'] == ['Storm C'] and 'Storm B' in s['changed']
    assert s['changed']['Storm B']['rg'] == [2.5, 2.52]
    md = summary_markdown(s)
    assert '1 new · ' in md and '1 retired' in md and 'rg: 2.5 → 2.52' in md
    s2 = summarize(old, new[:1])
    assert set(s2['dropped_from_raw']) == {'Storm B', 'Storm C'}


def test_validate_status_fields():
    from lanesight_core.arsenal.catalog import validate
    assert validate(ball('A', status='discontinued', discontinued_on='2026-10-26')) == []
    assert any('status' in e for e in validate(ball('A', status='gone')))
    assert any('current ball' in e for e in validate(ball('A', discontinued_on='2026-10-26')))
    assert any('YYYY-MM-DD' in e for e in validate(ball('A', status='discontinued', discontinued_on='Oct 2026')))


def test_cli_merge_refusal_exit_code(tmp_path, capsys):
    raw, fresh = tmp_path / 'storm.json', tmp_path / 'fresh.json'
    raw.write_text(json.dumps(lineup(*'ABCDEFGHIJ')))
    fresh.write_text(json.dumps(lineup('A')))
    assert main(['merge', str(raw), str(fresh), '--today', '2026-10-26']) == 2
    assert len(json.loads(raw.read_text())) == 10              # untouched on refusal


def test_digest_counts_every_ball_and_ignores_order():
    from pathlib import Path
    from lanesight_core.arsenal.refresh import catalog_digest
    cat = json.loads((Path(__file__).parents[1] / 'data/ball_catalog/catalog.json').read_text())
    n, h = catalog_digest(cat['balls'])
    assert n == len(cat['balls'])
    rows = [dict(manufacturer='B', name='x', source_hash='2'), dict(manufacturer='A', name='y', source_hash='1')]
    assert catalog_digest(rows) == catalog_digest(list(reversed(rows)))
