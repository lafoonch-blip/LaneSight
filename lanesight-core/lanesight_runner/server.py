"""FastAPI app for the local runner. Bound to 127.0.0.1 only. The page polls nothing: it listens on
/api/events (Server-Sent Events) and refetches /api/state when the version changes."""
from __future__ import annotations
import asyncio, csv, io, os, shutil, tempfile
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.responses import FileResponse, HTMLResponse, StreamingResponse, Response
from pydantic import BaseModel
from .probe import VIDEO_EXT

STATIC = os.path.join(os.path.dirname(__file__), 'static')

class SessionIn(BaseModel):
    kind: str = 'practice'
    handed: str | None = None
    ball_name: str | None = None
    ball_weight_lb: float | None = None
    ball_rg_in: float | None = None
    pattern_name: str | None = None
    pattern_length_ft: float | None = None

class SessionPatch(BaseModel):
    ball_name: str | None = None
    ball_weight_lb: float | None = None
    ball_rg_in: float | None = None
    pattern_name: str | None = None
    pattern_length_ft: float | None = None
    handed: str | None = None
    intent: dict | None = None
    notes: str | None = None

class ShotInputs(BaseModel):
    intent: dict | None = None
    hit_mark: str | None = None
    pins_override: list[int] | None = None
    clear_pins_override: bool = False
    kind_override: str | None = None
    sensor: dict | None = None
    rec_vote: str | None = None
    rec_note: str | None = None
    rec_followed: str | None = None
    ball_name: str | None = None
    ball_weight_lb: float | None = None
    ball_rg_in: float | None = None

def _clean_intent(d):
    if not d: return None
    out = {k: float(v) for k, v in d.items() if k in ('laydown_board', 'arrows_board', 'breakpoint_board') and v not in (None, '')}
    return out or None

def create_app(runner) -> FastAPI:
    app = FastAPI(title='LaneSight local runner')

    @app.get('/', response_class=HTMLResponse)
    def index():
        return open(os.path.join(STATIC, 'index.html')).read()

    @app.get('/api/state')
    def state(session_id: int | None = None):
        return runner.state(session_id)

    @app.get('/api/patterns')
    def patterns():
        from .oil import library
        return library()

    @app.get('/api/events')
    async def events():
        async def gen():
            v = -1
            while True:
                nv = await asyncio.to_thread(runner.wait_version, v, 15.0)
                if nv != v:
                    v = nv; yield f'data: {v}\n\n'
                else:
                    yield ': keepalive\n\n'
        return StreamingResponse(gen(), media_type='text/event-stream', headers={'Cache-Control': 'no-cache'})

    @app.post('/api/session')
    def start_session(body: SessionIn):
        if body.kind not in ('practice', 'league', 'tournament'): raise HTTPException(400, 'kind must be practice, league or tournament')
        sid = runner.db.start_session(**body.model_dump()); runner.bump(); return dict(id=sid)

    @app.patch('/api/session')
    def patch_session(body: SessionPatch):
        s = runner.db.active_session()
        if not s: raise HTTPException(409, 'no active session')
        kw = body.model_dump(exclude_unset=True)
        if 'intent' in kw: kw['intent_json'] = _clean_intent(kw.pop('intent'))
        runner.db.update_session(s['id'], **kw); runner.bump(); return dict(ok=True)

    @app.post('/api/session/end')
    def end_session():
        s = runner.db.active_session()
        if s: runner.db.end_session(s['id']); runner.bump()
        return dict(ok=True)

    @app.post('/api/shots/{sid}')
    def shot_inputs(sid: int, body: ShotInputs):
        shot = runner.db.shot(sid)
        if not shot: raise HTTPException(404, 'shot not found')
        kw = body.model_dump(exclude_unset=True)
        upd = {}
        if 'intent' in kw: upd['intent_json'] = _clean_intent(kw['intent'])
        if 'hit_mark' in kw:
            if kw['hit_mark'] not in (None, 'yes', 'no', 'unsure'): raise HTTPException(400, 'hit_mark must be yes, no or unsure')
            upd['hit_mark'] = kw['hit_mark']
        if kw.get('clear_pins_override'): upd['pins_override_json'] = None
        elif 'pins_override' in kw:
            p = sorted(set(kw['pins_override'] or []))
            if any(x < 1 or x > 10 for x in p): raise HTTPException(400, 'pins are 1-10')
            upd['pins_override_json'] = p
        if 'kind_override' in kw:
            if kw['kind_override'] not in (None, 'first', 'spare'): raise HTTPException(400, 'kind must be first or spare')
            upd['kind_override'] = kw['kind_override']
        if 'sensor' in kw:
            s = {k: float(v) for k, v in (kw['sensor'] or {}).items() if v not in (None, '')}
            upd['sensor_json'] = dict(s, vendor='ruby') if s else None
        for k in ('rec_vote', 'rec_note', 'rec_followed', 'ball_name', 'ball_weight_lb', 'ball_rg_in'):
            if k in kw: upd[k] = kw[k]
        runner.db.update_shot(sid, **upd)
        if any(k in upd for k in ('pins_override_json', 'intent_json', 'hit_mark', 'kind_override')): runner.render(sid)
        runner.bump()
        return runner.card(sid)

    @app.post('/api/shots/{sid}/retry')
    def retry(sid: int):
        shot = runner.db.shot(sid)
        if not shot: raise HTTPException(404, 'shot not found')
        runner.db.update_shot(sid, status='queued', error=None); runner.q.put(sid); runner.bump(); return dict(ok=True)

    @app.post('/api/upload')
    async def upload(file: UploadFile = File(...)):
        if not runner.db.active_session(): raise HTTPException(409, 'start a session first')
        ext = os.path.splitext(file.filename or '')[1].lower()
        if ext not in VIDEO_EXT: raise HTTPException(400, f'not a video file ({ext or "no extension"})')
        with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as tmp:
            shutil.copyfileobj(file.file, tmp); tmp_path = tmp.name
        try: sid = runner.ingest(tmp_path, original_name=file.filename)
        finally: os.unlink(tmp_path)
        return dict(id=sid)

    @app.get('/api/shots/{sid}/replay.png')
    def replay(sid: int):
        shot = runner.db.shot(sid)
        if not shot: raise HTTPException(404)
        p = runner.replay_path(sid)
        if not os.path.exists(p): raise HTTPException(404, 'no replay yet')
        return FileResponse(p, media_type='image/png', headers={'Cache-Control': 'no-store'})

    @app.get('/api/shots/{sid}/video')
    def video(sid: int):
        shot = runner.db.shot(sid)
        if not shot: raise HTTPException(404)
        p = shot['clip_path']                # after a windowed run this is the trimmed shot (SDR 8-bit for HDR)
        if not os.path.exists(p): raise HTTPException(404, 'clip not found')
        # content-type must match the container, or Chrome's media loader stalls on a .mov served as video/mp4
        ct = {'.mov': 'video/quicktime', '.m4v': 'video/mp4', '.mp4': 'video/mp4'}.get(os.path.splitext(p)[1].lower(), 'video/mp4')
        return FileResponse(p, media_type=ct, headers={'Cache-Control': 'no-store', 'Accept-Ranges': 'bytes'})

    @app.get('/api/shots/{sid}/thumb.jpg')
    def thumb(sid: int):
        shot = runner.db.shot(sid)
        if not shot or not shot.get('record'): raise HTTPException(404)
        p = shot['clip_path']; out = os.path.splitext(p)[0] + '_thumb.jpg'
        if not os.path.exists(out):                          # grab a frame at release time, cached next to the clip
            if not os.path.exists(p): raise HTTPException(404, 'clip not found')
            import subprocess
            t = (shot['record'].get('events') or {}).get('t_release') or 0
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', str(max(0, t)), '-i', p, '-frames:v', '1',
                            '-vf', 'scale=120:-1', out], capture_output=True)
            if not os.path.exists(out): raise HTTPException(404, 'could not grab a frame')
        return FileResponse(out, media_type='image/jpeg', headers={'Cache-Control': 'max-age=3600'})

    @app.get('/api/shots/{sid}/trajectory')
    def trajectory(sid: int):
        """Tracked ball path in video pixels (stabilized reference frame) + a lane(board,z)->image homography fit
        from the path, so the page can project the target line. Pixels overlay the raw frame directly only when
        camera motion is small (trimmed clips are ~0); the page gates on camera_motion_px."""
        shot = runner.db.shot(sid)
        if not shot or not shot.get('record'): raise HTTPException(404, 'no analysis')
        rec = shot['record']; tr = rec.get('trajectory') or {}
        pix = tr.get('pixel') or []
        if not pix: raise HTTPException(404, 'no tracked path for this shot')
        out = dict(pixel=pix, key_points=rec.get('key_points'),
                   camera_motion_px=(rec.get('video') or {}).get('camera_motion_px'),
                   lane_to_image=fit_lane_to_image(tr))
        return out

    @app.post('/api/speech')
    def speech(on: bool):
        runner.speaker.enabled = on and runner.speaker.cmd is not None; runner.bump(); return dict(speech=runner.speaker.enabled)

    @app.get('/api/sessions/{sid}/export.csv')
    def export(sid: int):
        sess = runner.db.session(sid)
        if not sess: raise HTTPException(404)
        _, shots, cards = runner.cards(sid)
        return Response(to_csv(cards), media_type='text/csv',
                        headers={'Content-Disposition': f'attachment; filename="lanesight_session_{sid}.csv"'})

    return app

def fit_lane_to_image(trajectory):
    """Homography mapping lane coordinates (absolute board, z ft) -> image pixels, fitted from the shot's own
    tracked path (trajectory.lane <-> trajectory.pixel, same points in order). The hooking path spans enough of
    the lane plane to fit well (sub-pixel on real shots). Returns a 3x3 list, or None if there aren't enough
    points. Used only to draw the target line; the ball path uses the stored pixels directly."""
    lane = trajectory.get('lane') or []; pix = trajectory.get('pixel') or []
    n = min(len(lane), len(pix))
    if n < 6: return None
    try:
        import numpy as np, cv2
        L = np.array([[p['board'], p['z_ft']] for p in lane[:n]], np.float64)
        P = np.array([[p['x'], p['y']] for p in pix[:n]], np.float64)
        H, _ = cv2.findHomography(L, P, 0)
        return None if H is None else [[round(float(v), 6) for v in row] for row in H]
    except Exception:
        return None

def to_csv(cards) -> str:
    from .card import DISPLAY, SENSOR_FIELDS
    cols = ['n', 'status', 'error', 'kind', 'created_at', 'original_name', 'ball', 'ball_weight_lb', 'fps', 'resolution', 'tier']
    for key, *_ in DISPLAY: cols += [key, f'{key}_status', f'{key}_conf']
    cols += ['power', 'energy_j', 'pins_standing', 'pins_uncertain', 'pins_source', 'strike', 'hit', 'classification',
             'intent_laydown', 'intent_arrows', 'intent_breakpoint', 'hit_mark', 'primary_rec', 'rec_vote', 'rec_followed', 'rec_note']
    cols += [f'ruby_{k}' for k in SENSOR_FIELDS] + ['analyze_s', 'total_s']
    buf = io.StringIO(); w = csv.DictWriter(buf, fieldnames=cols, extrasaction='ignore'); w.writeheader()   # axis_tilt (Ruby) has its own ruby_* column
    for c in cards:
        r = dict(n=c['n'], status=c['status'], error=c.get('error'), kind=c['kind'], created_at=c['created_at'],
                 original_name=c.get('original_name'), ball=c.get('ball'), ball_weight_lb=c.get('ball_weight_lb'))
        p = c.get('probe') or {}
        r.update(fps=p.get('measured_fps'), resolution=f"{p.get('width')}x{p.get('height')}" if p else None,
                 tier=(c.get('capture') or {}).get('tier'))
        for m in c.get('metrics') or []:
            r[m['key']] = m['value']; r[f"{m['key']}_status"] = m['status']; r[f"{m['key']}_conf"] = m.get('confidence')
        pw = c.get('power') or {}; r.update(power=pw.get('value'), energy_j=pw.get('energy_j'))
        pins = c.get('pins')
        if pins:
            r.update(pins_standing='-'.join(map(str, pins['standing'])), pins_uncertain='-'.join(map(str, pins['uncertain'])),
                     pins_source=pins['source'], strike=pins['strike'])
        ins = c.get('insights') or {}
        r.update(hit=(c.get('hit') or {}).get('hit'), classification=ins.get('classification'),
                 primary_rec=(ins.get('recommendations') or [{}])[0].get('reason'))
        it = c.get('intent') or {}
        r.update(intent_laydown=it.get('laydown_board'), intent_arrows=it.get('arrows_board'), intent_breakpoint=it.get('breakpoint_board'),
                 hit_mark=c.get('hit_mark'), rec_vote=c.get('rec_vote'), rec_followed=c.get('rec_followed'), rec_note=c.get('rec_note'))
        for k in SENSOR_FIELDS: r[f'ruby_{k}'] = (c.get('sensor') or {}).get(k)
        t = c.get('timings') or {}; r.update(analyze_s=t.get('analyze_s'), total_s=t.get('total_s'))
        w.writerow(r)
    return buf.getvalue()
