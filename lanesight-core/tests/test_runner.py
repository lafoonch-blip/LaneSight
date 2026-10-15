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

# ---------- shot-window trimming ----------
def make_burst_clip(path, fps=60, pre=60, burst=90, post=60):
    """A clip that is static, then has a bright square sweeping up the lower-centre (the 'shot'), then static.
    The background is non-periodic texture so phase correlation locks to zero shift on the static frames, the
    way it does on a real lane; a featureless (or periodic) background would read as all-motion."""
    import cv2, numpy as np
    w, h = 640, 360
    vw = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*'mp4v'), fps, (w, h))
    bg = cv2.GaussianBlur((np.random.RandomState(0).rand(h, w, 1) * 120 + 40).astype(np.uint8).repeat(3, 2), (3, 3), 0)
    for k in range(pre): vw.write(bg.copy())
    for k in range(burst):                                                  # square sweeps up through the lane
        f = bg.copy(); y = int(h*0.85 - k/burst * h*0.45); x = int(w*0.5)
        cv2.rectangle(f, (x-28, y-28), (x+28, y+28), (255, 255, 255), -1); vw.write(f)
    for k in range(post): vw.write(bg.copy())
    vw.release(); return path

@needs_ffmpeg
def test_detect_window_finds_the_burst(tmp_path):
    from lanesight_runner.trim import detect_window
    src = make_burst_clip(str(tmp_path / 'burst.mp4'))                      # static 0-1s, shot 1-2.5s, static 2.5-3.5s
    t0, t1, info = detect_window(src, lead=0.5, tail=0.5)
    assert t0 is not None and info.get('burst')                             # a shot-like burst was detected
    bs, be = info['burst']
    assert 0.8 < bs < 1.6 and 2.0 < be < 3.0                                # burst ~ the moving-square window
    assert t0 < bs and t1 > be                                              # lead/tail margins applied

@needs_ffmpeg
def test_detect_window_no_burst_falls_back(tmp_path):
    from lanesight_runner.trim import detect_window
    src = make_clip(str(tmp_path / 'static.mp4'), size='640x360', secs=2)   # testsrc: no shot-like burst
    t0, t1, info = detect_window(src)
    assert t0 is None and t1 is None and 'reason' in info                   # caller analyses the whole clip

@needs_ffmpeg
def test_trim_clip_shortens(tmp_path):
    from lanesight_runner.trim import trim_clip
    src = str(tmp_path / 'full.mp4')                                        # frequent keyframes (iPhone-like) so a
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=size=640x360:rate=60', '-t', '4',
                    '-pix_fmt', 'yuv420p', '-c:v', 'libx264', '-preset', 'ultrafast', '-g', '15', src], check=True)
    dst = trim_clip(src, str(tmp_path / 'cut.mov'), 1.0, 2.5)               # stream-copy cut cleanly on a keyframe
    p = probe(dst)
    assert 1.0 < p['duration_s'] < 2.0 and p['frames'] < 130               # ~1.5 s window, not the full 240 frames

def test_keep_only_trimmed_replaces_and_cleans(tmp_path):
    base = str(tmp_path / 'shot_001')
    clip, trim, sdr, cache = base + '.mov', base + '_trim.mov', base + '_trim_sdr.mov', base + '_trim_sdr_stab.pkl'
    for pth, txt in [(clip, 'FULL ORIGINAL'), (trim, 'TRIMMED SHOT'), (sdr, 'x'), (cache, 'x')]:
        open(pth, 'w').write(txt)
    Runner(str(tmp_path / 'data'), speaker=Quiet())._keep_only_trimmed(clip, trim, base)
    assert open(clip).read() == 'TRIMMED SHOT'                             # the full clip is replaced in place
    assert not os.path.exists(trim) and not os.path.exists(sdr) and not os.path.exists(cache)   # working files gone

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
    vid = cl.get(f'/api/shots/{sid}/video')
    assert vid.status_code == 200 and vid.headers['content-type'] in ('video/quicktime', 'video/mp4')
    tj = cl.get(f'/api/shots/{sid}/trajectory').json()
    assert tj['pixel'] and {'t', 'x', 'y'} <= set(tj['pixel'][0]) and tj['key_points']
    assert len(tj['lane_to_image']) == 3 and len(tj['lane_to_image'][0]) == 3        # fitted homography
    csv = cl.get(f"/api/sessions/{st['session']['id']}/export.csv").text
    assert 'ball_speed' in csv.splitlines()[0] and ',10,' in csv.splitlines()[1]

def test_fit_lane_to_image_recovers_a_known_homography():
    import numpy as np, cv2
    from lanesight_runner.server import fit_lane_to_image
    H0 = np.array([[12.0, 0.5, 100.0], [1.0, -9.0, 1700.0], [0.0, -0.01, 1.0]])   # arbitrary lane->image
    lane = [(b, z) for b in (8, 12, 16, 20) for z in (0, 15, 38, 59)]             # a spread of lane points
    pix = cv2.perspectiveTransform(np.array(lane, float).reshape(-1, 1, 2), H0).reshape(-1, 2)
    tr = dict(lane=[dict(board=b, z_ft=z) for b, z in lane], pixel=[dict(x=x, y=y) for x, y in pix])
    H = fit_lane_to_image(tr)
    assert H is not None
    got = cv2.perspectiveTransform(np.array([[[14.0, 30.0]]]), np.array(H)).reshape(2)   # project a new point
    want = cv2.perspectiveTransform(np.array([[[14.0, 30.0]]]), H0).reshape(2)
    assert np.allclose(got, want, atol=1.0)
    assert fit_lane_to_image(dict(lane=[], pixel=[])) is None                     # too few points -> None

# ---------- HDR ----------
def make_hdr_clip(path, fps=60, secs=1, transfer='arib-std-b67'):
    # libx265 + numeric color codes: libx264 on some ffmpeg builds drops the transfer tag, so probe() wouldn't see HDR.
    # transfer codes: arib-std-b67 (HLG)=18, smpte2084 (PQ)=16; primaries/matrix bt2020=9.
    trc = '16' if transfer == 'smpte2084' else '18'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', f'testsrc=size=640x360:rate={fps}', '-t', str(secs),
                    '-pix_fmt', 'yuv420p10le', '-c:v', 'libx265', '-preset', 'ultrafast',
                    '-x265-params', f'colorprim=bt2020:transfer={transfer}:colormatrix=bt2020nc',
                    '-color_trc', trc, '-color_primaries', '9', '-colorspace', '9', path], check=True)
    return path

@needs_ffmpeg
def test_hdr_detected_and_converted_with_same_frame_times(tmp_path):
    # Runs on either conversion path: ffmpeg zscale when present, else the portable numpy HLG tone-map.
    from lanesight_runner.probe import convert_sdr, _has
    src = make_hdr_clip(str(tmp_path / 'hdr.mov'))
    p = probe(src)
    assert p['hdr'] and any('HDR' in w for w in p['warnings'])
    info = convert_sdr(src, str(tmp_path / 'sdr.mov'))
    q = probe(str(tmp_path / 'sdr.mov'))
    assert not q['hdr'] and q['decoded_frames'] == 60 and info['frames'] == 60 and info['timing_source'] == 'original clip'
    assert info['method'].startswith('zscale' if _has('filters', 'zscale') else 'hlg-numpy')

@needs_ffmpeg
def test_convert_sdr_refuses_pq_without_zscale(tmp_path):
    # PQ needs a different inverse curve than HLG; the numpy fallback refuses it rather than guessing.
    from lanesight_runner.probe import convert_sdr, _has
    if _has('filters', 'zscale'): pytest.skip('zscale present: PQ is handled by ffmpeg')
    src = make_hdr_clip(str(tmp_path / 'pq.mov'), transfer='smpte2084')
    with pytest.raises(ClipError, match='smpte2084'):
        convert_sdr(src, str(tmp_path / 'out.mov'))

def test_hlg_to_709_restores_neutral_grey_and_shape():
    import numpy as np
    from lanesight_runner.probe import _hlg_to_709
    grey = np.full((3, 4, 3), 128, np.uint8)
    out = _hlg_to_709(grey)
    assert out.shape == grey.shape and out.dtype == np.uint8
    assert abs(int(out[..., 0].mean()) - int(out[..., 2].mean())) <= 2   # grey stays neutral (R≈G≈B)

@needs_ffmpeg
def test_runner_analyzes_sdr_copy_of_hdr_clip(tmp_path):
    seen = {}
    def an(video, out_prefix, handed=None, log=print, timing_video=None):     # TEST ONLY: records what the runner passed in
        seen.update(video=video, prefix=out_prefix, timing=timing_video); return val('IMG_8754')
    r = Runner(tmp_path / 'data', analyzer=an, speaker=Quiet())
    r.db.start_session(kind='practice'); sid = r.ingest(make_hdr_clip(str(tmp_path / 'IMG_1.MOV'))); r.q.get(); r.process(sid)
    s = r.db.shot(sid)
    assert s['status'] == 'done' and seen['video'].endswith('_sdr.mov') and seen['prefix'].endswith('_sdr')
    assert seen['timing'] == s['clip_path']                      # frame times come from the original clip
    assert s['probe']['sdr_conversion']['frames'] == 60 and 'convert_s' in s['timings']


@needs_ffmpeg
def test_stabilize_rejects_mismatched_timing_source(tmp_path):
    from lanesight_core.cv.stabilize import stabilize
    a = make_clip(str(tmp_path / 'a.mp4'), secs=1); b = make_clip(str(tmp_path / 'b.mp4'), secs=2)
    with pytest.raises(RuntimeError, match='timing source'):
        stabilize(a, log=lambda m: None, timing_path=b)
