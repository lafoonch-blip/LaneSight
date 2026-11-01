"""LaneSight Labeler: clip lookup, exact frame indexing, label save + export, and the HTTP API."""
import json
import os
import threading
import urllib.request

import cv2
import numpy as np
import pytest

from lanesight_core.labeler.core import ClipFinder, FrameSource, LabelStore, load_task, clip_complete
from lanesight_core.labeler.server import make_server


def _make_clip(path, n=90, fps=30):
    """Each frame encodes its own index as a gray level band so the test can verify exact indexing."""
    w = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*'mp4v'), fps, (160, 120))
    for i in range(n):
        img = np.zeros((120, 160, 3), np.uint8)
        img[:, : (i % 160) + 1] = 255           # bar width = index + 1
        w.write(img)
    w.release()


def _bar(jpeg):
    img = cv2.imdecode(np.frombuffer(jpeg, np.uint8), cv2.IMREAD_GRAYSCALE)
    return int((img[60] > 128).sum()) - 1


@pytest.fixture()
def env(tmp_path):
    data = tmp_path / 'LaneSightData' / 'training_videos' / 'form videos'
    data.mkdir(parents=True)
    _make_clip(str(data / 'IMG_0001.mov'))
    tasks = tmp_path / 'tasks'; tasks.mkdir()
    (tasks / 'demo.json').write_text(json.dumps({
        'title': 'Demo', 'clips': [{'id': 'IMG_0001', 'hints': {'a': 40}, 'static': {'view': 'side'}}, 'IMG_9999'],
        'events': [{'id': 'a', 'label': 'A', 'export_key': 'a_frame', 'export_unit': 'frame'},
                   {'id': 'b', 'label': 'B', 'export_key': 'b_s', 'export_unit': 'seconds'}],
        'fields': [{'id': 'steps', 'type': 'int', 'required': True}],
        'export': {'path': 'out/demo_export.json', 'wrap': 'clips', 'add_fps': True}}))
    return tmp_path, tasks


def test_finder_searches_subfolders_case_insensitively(env):
    root, _ = env
    f = ClipFinder([str(root / 'LaneSightData')])
    assert f.find('img_0001').endswith('form videos/IMG_0001.mov')
    assert f.find('IMG_9999') is None


def test_frames_are_exact_in_both_directions(env):
    root, _ = env
    src = FrameSource(str(root / 'LaneSightData/training_videos/form videos/IMG_0001.mov'), cache_frames=20)
    assert src.n == 90 and abs(src.fps - 30) < 0.1
    for idx in (0, 1, 45, 44, 89, 10, 70, 3):          # forward, back, big jumps (cache misses)
        assert _bar(src.get(idx)['jpeg']) == idx, idx
    assert src.get(500)['index'] == 89                  # clamped


def test_save_complete_and_export(env, tmp_path):
    root, tasks = env
    t = load_task(str(tasks / 'demo.json'))
    st = LabelStore(str(tmp_path / 'labels'), str(tmp_path))
    st.update(t, 'IMG_0001', {'event': 'a', 'frame': 45, 'status': 'set'}, fps=30.0)
    d = st.update(t, 'IMG_0001', {'event': 'b', 'status': 'not_visible'}, fps=30.0)
    assert not clip_complete(t, d['clips']['IMG_0001'])        # required field missing
    d = st.update(t, 'IMG_0001', {'field': 'steps', 'value': '4'})
    c = d['clips']['IMG_0001']
    assert c['events']['a'] == {'frame': 45, 't_s': 1.5, 'status': 'set'}
    assert c['fields']['steps'] == 4 and clip_complete(t, c)
    ex = json.loads((tmp_path / 'out/demo_export.json').read_text())
    assert ex['clips']['IMG_0001'] == {'view': 'side', 'a_frame': 45, 'b_s': None, 'steps': 4, 'fps': 30.0}
    assert ex['clips']['IMG_9999']['a_frame'] is None
    with pytest.raises(ValueError):
        st.update(t, 'IMG_0001', {'event': 'nope', 'frame': 1})
    d = st.update(t, 'IMG_0001', {'event': 'a', 'status': 'clear'})
    assert 'a' not in d['clips']['IMG_0001']['events']


def test_http_api_end_to_end(env, tmp_path):
    root, tasks = env
    srv = make_server(0, task_dir=str(tasks), label_dir=str(tmp_path / 'labels'),
                      search=[str(root / 'LaneSightData')], repo_root=str(tmp_path))
    th = threading.Thread(target=srv.serve_forever, daemon=True); th.start()
    base = f'http://127.0.0.1:{srv.server_address[1]}'
    try:
        get = lambda p: urllib.request.urlopen(base + p)
        assert b'LaneSight Labeler' in get('/').read()
        assert json.load(get('/api/tasks'))['tasks'][0]['total'] == 2
        meta = json.load(get('/api/clip/IMG_0001'))
        assert meta['found'] and meta['frames'] == 90
        assert json.load(get('/api/clip/IMG_9999')) == {'found': False}
        r = get('/api/frame/IMG_0001/33')
        assert r.headers['X-Frame-Index'] == '33' and _bar(r.read()) == 33
        req = urllib.request.Request(base + '/api/label/demo/IMG_0001', method='POST',
                                     data=json.dumps({'event': 'a', 'frame': 33, 'status': 'set'}).encode(),
                                     headers={'Content-Type': 'application/json'})
        t = json.load(urllib.request.urlopen(req))
        assert t['clips'][0]['labels']['events']['a']['frame'] == 33
        bad = urllib.request.Request(base + '/api/label/demo/NOT_A_CLIP', method='POST', data=b'{}')
        with pytest.raises(urllib.error.HTTPError) as e:
            urllib.request.urlopen(bad)
        assert e.value.code == 404
    finally:
        srv.shutdown()


def test_repo_task_files_are_valid():
    from lanesight_core.labeler.core import TASK_DIR, load_tasks
    ts = load_tasks(TASK_DIR)
    assert {'pin_anchor_truth', 'form_events'} <= set(ts)
    for t in ts.values():
        assert 'error' not in t, t
        ids = [e['id'] for e in t['events']]
        assert len(ids) == len(set(ids))
        for c in t['clips']:
            assert set(c['hints']) <= set(ids)
