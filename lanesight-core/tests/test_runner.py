"""Local runner tests. Video analysis itself is covered by the validation clips (not in the repo); here the
analyzer is replaced by one that returns the real pipeline output stored in validation/, so everything around
it (ingest, timing checks, cards, inputs, stats, API, CSV) is exercised for real."""
import json, os, shutil, subprocess, time
import pytest
from lanesight_core.power import power, E_REF_J
from lanesight_runner.probe import probe, ClipError
from lanesight_runner import card as cardmod
from lanesight_runner.core import Runner

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VAL = os.path.join(ROOT, 'validation')
needs_ffmpeg = pytest.mark.skipif(not shutil.which('ffmpeg'), reason='ffmpeg not installed')

def val(name): return json.load(open(os.path.join(VAL, f'{name}_shot.json')))

def make_clip(path, fps=60, size='1920x1080', secs=1):
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', f'testsrc=size={size}:rate={fps}', '-t', str(secs),
                    '-pix_fmt', 'yuv420p', '-c:v', 'libx264', '-preset', 'ultrafast', path], check=True)
    return path

class Quiet:
    cmd = None; enabled = False; said = []
    def say(self, t): self.said.append(t)

# ---------- Power ----------
def test_power_reference_and_example():
    assert round(E_REF_J) == 267
    p = power(15, 16.5, 400)
    assert p['value'] == 78 and p['energy_j'] == 209 and 'RG assumed' in p['why']
    assert power(16, 25, 600)['value'] == 100

def test_power_never_guesses_missing_inputs():
    p = power(None, 16.5, 400)
    assert p['value'] is None and p['status'] == 'unavailable' and 'ball weight' in p['why']

# ---------- probe ----------
@needs_ffmpeg
def test_probe_60fps(tmp_path):
    p = probe(make_clip(str(tmp_path / 'a.mp4'), fps=60, size='640x360'))
    assert abs(p['measured_fps'] - 60) < 0.5 and p['frames'] == 60 and p['decoded_frames'] == 60
    assert any('below 1080p' in w for w in p['warnings'])

@needs_ffmpeg
def test_probe_30fps_warns_loft(tmp_path):
    p = probe(make_clip(str(tmp_path / 'b.mp4'), fps=30, size='1920x1080', secs=2))
    assert any('loft is unavailable' in w for w in p['warnings'])

def test_probe_rejects_non_video(tmp_path):
    f = tmp_path / 'x.mov'; f.write_text('not a video')
    with pytest.raises(ClipError): probe(str(f))

# ---------- cards ----------
def row(i, n, rec, **kw):
    return dict(dict(id=i, n=n, status='done', created_at='2026-10-14T20:00:00+00:00', record=rec, ball_name='Phaze II',
                     ball_weight_lb=15.0, ball_rg_in=None,
                     probe=dict(measured_fps=60.0, short_side_px=1080, width=1920, height=1080, warnings=[])), **kw)

SESSION = dict(id=1, pattern_length_ft=41)

def test_card_tiers_and_leave():
    c = cardmod.build_cards(SESSION, [row(1, 1, val('IMG_8754'))])[0]
    st = {m['key']: m for m in c['metrics']}
    assert c['capture']['tier'] == 'standard'
    assert st['ball_speed']['status'] == 'guaranteed' and st['ball_speed']['value'] == 17.0
    assert st['rev_rate']['status'] == 'best_effort'          # calibrated estimate until blind validation
    assert c['pins']['standing'] == [3, 6, 10] and c['pins']['uncertain'] == [9]
    r = c['insights']['recommendations'][0]
    assert r['type'] == 'move' and r['direction'] == 'right'
    assert c['spare_plan']['key_pin'] == 3
    assert c['power']['value'] is not None and c['power']['status'] == 'best_effort'
    assert c['speech'].startswith('Left 3 6 10.') and 'Move right' in c['speech']

def test_30fps_loft_unavailable_with_reason():
    r = row(1, 1, val('IMG_8752')); r['probe'] = dict(r['probe'], measured_fps=30.0)
    loft = {m['key']: m for m in cardmod.build_cards(SESSION, [r])[0]['metrics']}['loft']
    assert loft['value'] is None and loft['status'] == 'unavailable' and '55 fps' in loft['why']

def test_spare_follows_leave_and_pin_correction():
    leave, strike = val('IMG_8754'), val('IMG_8751')
    cards = cardmod.build_cards(SESSION, [row(1, 1, leave), row(2, 2, strike), row(3, 3, strike)])
    assert [c['kind'] for c in cards] == ['first', 'spare', 'first']
    assert cards[1]['speech'].startswith('Spare made')
    # correcting shot 1 to a strike makes shot 2 a first ball
    cards = cardmod.build_cards(SESSION, [row(1, 1, leave, pins_override=[]), row(2, 2, strike)])
    assert cards[0]['pins']['strike'] and cards[0]['pins']['source'] == 'corrected'
    assert [c['kind'] for c in cards] == ['first', 'first']

def test_hit_mark_no_means_no_line_move():
    c = cardmod.build_cards(SESSION, [row(1, 1, val('IMG_8754'), hit_mark='no', intent=dict(arrows_board=10))])[0]
    assert c['insights']['classification'] == 'EXECUTION_MISS'
    assert c['insights']['recommendations'][0]['move_feet'] == 0

def test_sensor_variance_and_stats():
    ruby = json.load(open(os.path.join(VAL, 'IMG_8754_ruby.json')))
    rows = [row(1, 1, val('IMG_8754'), sensor=ruby), row(2, 2, val('IMG_8751')), row(3, 3, val('IMG_8752')), row(4, 4, val('IMG_8753'))]
    cards = cardmod.build_cards(SESSION, rows)
    v = cards[0]['sensor_variance']['compared']['ball_speed']
    assert v['sensor'] == 17.0 and abs(v['diff']) < 0.1
    st = cardmod.session_stats(cards, rows)
    assert st['first_balls'] == 3 and st['spare_attempts'] == 1 and st['spares_made'] == 1
    assert st['sensor_variance']['ball_speed']['n'] == 1

# ---------- runner: watch folder + queue ----------
def fake_analyzer(video, out_prefix, handed=None, log=print):
    """TEST ONLY: returns the stored real pipeline output for IMG_8754 instead of analyzing the synthetic clip."""
    log('fake analyzer'); return val('IMG_8754')

@needs_ffmpeg
def test_watch_folder_ingest(tmp_path):
    watch = tmp_path / 'Downloads'; watch.mkdir()
    make_clip(str(watch / 'old.mov'))                                     # present at startup: ignored
    r = Runner(tmp_path / 'data', watch_dir=str(watch), analyzer=fake_analyzer, speaker=Quiet(), stable_s=0.2)
    r._seen = r._snapshot()
    r.db.start_session(kind='practice', ball_name='Phaze II', ball_weight_lb=15.0)
    (watch / 'notes.txt').write_text('ignore me')
    clip = make_clip(str(tmp_path / 'IMG_9000.MOV')); shutil.copy(clip, watch / 'IMG_9000.MOV')
    r.poll_once(); assert r.q.qsize() == 0                                # not yet stable
    time.sleep(0.3); r.poll_once(); assert r.q.qsize() == 1
    r.poll_once(); assert r.q.qsize() == 1                                # no double ingest
    sid = r.q.get(); r.process(sid)
    s = r.db.shot(sid)
    assert s['status'] == 'done' and s['original_name'] == 'IMG_9000.MOV' and os.path.exists(s['clip_path'])
    assert os.path.exists(watch / 'IMG_9000.MOV')                         # original untouched
    assert s['timings']['total_s'] >= s['timings']['analyze_s'] and s['timings']['steps']
    assert os.path.exists(r.replay_path(sid))
    assert r.state()['cards'][0]['pins']['standing'] == [3, 6, 10]

def test_failed_analysis_is_visible(tmp_path):
    f = tmp_path / 'bad.mov'; f.write_text('nope')
    r = Runner(tmp_path / 'data', analyzer=fake_analyzer, speaker=Quiet())
    r.db.start_session(kind='practice'); sid = r.ingest(str(f)); r.q.get(); r.process(sid)
    s = r.db.shot(sid)
    assert s['status'] == 'failed' and s['error'].startswith('Clip rejected') and s['record'] is None
    assert r.card(sid)['speech'] == 'Shot could not be analyzed.'

# ---------- API ----------
@needs_ffmpeg
def test_api_flow(tmp_path):
    from fastapi.testclient import TestClient
    from lanesight_runner.server import create_app
    r = Runner(tmp_path / 'data', analyzer=fake_analyzer, speaker=Quiet())
    cl = TestClient(create_app(r))
    assert cl.get('/').status_code == 200
    assert cl.post('/api/upload', files={'file': ('a.mov', b'x')}).status_code == 409   # no session
    assert cl.post('/api/session', json=dict(kind='practice', ball_name='Phaze II', ball_weight_lb=15)).status_code == 200
    assert cl.patch('/api/session', json=dict(intent=dict(arrows_board=13, breakpoint_board=''))).status_code == 200
    clip = make_clip(str(tmp_path / 'c.mov'))
    sid = cl.post('/api/upload', files={'file': ('IMG_1.MOV', open(clip, 'rb'))}).json()['id']
    r.process(r.q.get())
    st = cl.get('/api/state').json()
    c = st['cards'][0]
    assert c['status'] == 'done' and c['intent'] == {'arrows_board': 13.0}
    c = cl.post(f'/api/shots/{sid}', json=dict(hit_mark='yes', pins_override=[10], sensor=dict(speed_mph=17.0, rev_rate_rpm=''))).json()
    assert c['pins']['standing'] == [10] and c['hit_mark'] == 'yes' and c['sensor'] == {'speed_mph': 17.0, 'vendor': 'ruby'}
    assert cl.post(f'/api/shots/{sid}', json=dict(pins_override=[11])).status_code == 400
    assert cl.get(f'/api/shots/{sid}/replay.png').status_code == 200
    csv = cl.get(f"/api/sessions/{st['session']['id']}/export.csv").text
    assert 'ball_speed' in csv.splitlines()[0] and ',10,' in csv.splitlines()[1]

# ---------- HDR ----------
def make_hdr_clip(path, fps=60, secs=1):
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', f'testsrc=size=640x360:rate={fps}', '-t', str(secs),
                    '-pix_fmt', 'yuv420p10le', '-c:v', 'libx264', '-preset', 'ultrafast', '-color_primaries', 'bt2020',
                    '-color_trc', 'arib-std-b67', '-colorspace', 'bt2020nc', path], check=True)
    return path

@needs_ffmpeg
def test_hdr_detected_and_converted_with_same_frame_times(tmp_path):
    from lanesight_runner.probe import convert_sdr, frame_times, _has
    if not _has('filters', 'zscale'): pytest.skip('ffmpeg without zscale')
    src = make_hdr_clip(str(tmp_path / 'hdr.mov'))
    p = probe(src)
    assert p['hdr'] and any('HDR' in w for w in p['warnings'])
    info = convert_sdr(src, str(tmp_path / 'sdr.mov'))
    q = probe(str(tmp_path / 'sdr.mov'))
    assert not q['hdr'] and q['decoded_frames'] == 60 and info['frames'] == 60 and info['max_shift_ms'] <= 2

@needs_ffmpeg
def test_runner_analyzes_sdr_copy_of_hdr_clip(tmp_path):
    from lanesight_runner.probe import _has
    if not _has('filters', 'zscale'): pytest.skip('ffmpeg without zscale')
    seen = {}
    def an(video, out_prefix, handed=None, log=print):     # TEST ONLY: records what the runner passed in
        seen.update(video=video, prefix=out_prefix); return val('IMG_8754')
    r = Runner(tmp_path / 'data', analyzer=an, speaker=Quiet())
    r.db.start_session(kind='practice'); sid = r.ingest(make_hdr_clip(str(tmp_path / 'IMG_1.MOV'))); r.q.get(); r.process(sid)
    s = r.db.shot(sid)
    assert s['status'] == 'done' and seen['video'].endswith('_sdr.mov') and seen['prefix'].endswith('_sdr')
    assert s['probe']['sdr_conversion']['frames'] == 60 and 'convert_s' in s['timings']
