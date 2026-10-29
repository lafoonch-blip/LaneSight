"""FastAPI app for the Mac service (HANDOFF §3). Binds to localhost; exposed only via `tailscale serve`.
The end-to-end shot path (sessions -> shots upload -> serial analyze job -> result -> score recompute ->
summary -> feedback -> CSV) is implemented; the remaining §3 endpoints are declared and return 501 until
their DB-backed handlers land, so the OpenAPI contract lists the full surface honestly.
"""
from __future__ import annotations
import json
import os
import re
import uuid
import time
from pathlib import Path

import shutil

from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, Response, Body, Header
from fastapi.responses import FileResponse, Response

from . import API_VERSION, APP_COMPAT
from . import engines
from . import userauth
from .auth import current_user
from .config import settings
from .jobs import SerialJobQueue
from .store import get_store, session_csv
from .profile_validation import validate_profile_patch, ProfileValidationError
from lanesight_core.models.shot import ALGO_VERSION
from lanesight_core.score import SCORE_VERSION
from lanesight_core.benchmarks import BENCHMARK_VERSION
from lanesight_core.form import spot_check

# DEC-106 Phase 0: Cloud Run reports os.cpu_count()=8 but allocates only 4 vCPUs, so OpenCV defaults to 8
# threads on 4 vCPUs → 2x oversubscription that dominates the stabilize/warp stages (OpenCV is NOT controlled
# by OMP/OPENBLAS env). Cap OpenCV threads to the allocated vCPUs when the cap env is set. No-op locally.
_cpu_cap = os.environ.get('LANESIGHT_CPU_THREADS') or os.environ.get('LANESIGHT_CV_WORKERS')
if _cpu_cap:
    try:
        import cv2 as _cv2
        _cv2.setNumThreads(max(1, int(_cpu_cap)))
    except Exception:
        pass

DATA_ROOT = Path(os.environ.get('LANESIGHT_DATA', os.path.expanduser('~/LaneSightData')))
_queue = SerialJobQueue()
app = FastAPI(title='LaneSight API', version=API_VERSION)


# ----------------------------------------------------------------- §2 ops instrumentation (DEC-098)
_HEXSEG = re.compile(r'^[0-9a-fA-F]{8,}$|^[0-9a-fA-F-]{20,}$')      # uuid/hex id segment
_METRICS_SKIP = ('/health', '/docs', '/openapi', '/redoc', '/favicon')


def _templatize_path(path: str) -> str:
    """Collapse id-like path segments to ':id' so api_request stays low-cardinality and carries no ids."""
    return '/'.join(':id' if _HEXSEG.match(seg or '') else seg for seg in path.split('/'))


def _attempt_cost(duration_ms: int, clip: dict | None) -> dict | None:
    """DEC-098 §2 (M1): best_effort compute + egress inputs for cost reporting. Resource-seconds are MEASURED
    (duration x the Cloud Run vCPU/GiB config); no dollars here — ops.cost_daily applies sourced rates, and
    returns NULL until the owner enters them. Never raises."""
    try:
        compute_s = round((duration_ms or 0) / 1000.0, 2)
        vcpu = float(os.environ.get('LANESIGHT_VCPU', '4'))
        gib = float(os.environ.get('LANESIGHT_GIB', '4'))
        bytes_ = (clip or {}).get('bytes')
        egress_mb = round(bytes_ / 1048576.0, 2) if bytes_ else None
        return {k: v for k, v in {
            'basis': 'best_effort', 'compute_s': compute_s, 'vcpu': vcpu, 'gib': gib,
            'vcpu_s': round(compute_s * vcpu, 2), 'gib_s': round(compute_s * gib, 2),
            'egress_mb': egress_mb,
            'rate_ref': os.environ.get('LANESIGHT_COST_RATE_REF', 'cloud_run_us-east1'),
        }.items() if v is not None}
    except Exception:
        return None


@app.middleware('http')
async def _ops_request_metrics(request, call_next):
    """DEC-098 §2 (M2): record one api_request per call (best-effort; never fails the request). No bodies,
    tokens or query strings — only method, templated path, status, latency, env/revision."""
    t = time.monotonic()
    response = await call_next(request)
    try:
        path = request.url.path
        if not any(path == s or path.startswith(s) for s in _METRICS_SKIP):
            get_store().log_api_request({
                'method': request.method, 'path': _templatize_path(path),
                'status': response.status_code, 'duration_ms': int((time.monotonic() - t) * 1000),
                'env': 'live' if os.environ.get('K_REVISION') else 'dev',
                'api_revision': os.environ.get('K_REVISION'),
            })
    except Exception as me:
        print(f'api_request log skipped ({me})')
    return response


# Consent-aware product events accepted at /events (schema registry — unknown names are dropped).
_PRODUCT_EVENTS = {'app_opened', 'session_started', 'first_shot_analyzed', 'screen_view',
                   'upload_started', 'analysis_completed', 'analysis_failed'}


# ----------------------------------------------------------------- analysis job
def _upload_dedupe_on() -> bool:
    """DEC-086: upload de-duplication is OFF by default so the same clip can be uploaded/analyzed repeatedly
    for testing. Turn it on with LANESIGHT_UPLOAD_DEDUPE=1. (Live-shot retry idempotency is separate and
    always on — it's a dropped-connection guard, not upload dedupe.)"""
    return os.environ.get('LANESIGHT_UPLOAD_DEDUPE') == '1'


_PROCESS_START = time.monotonic()      # DEC-092 P0: a job within ~20s of process start hit a cold instance
_COLD_START_WINDOW_S = 20.0


def _clip_info(probe) -> dict:
    """Clip facts for the analysis-attempt log (DEC-086). Captures the camera/recording characteristics we
    need to correlate framing with analysis outcomes: resolution, rotation, fps (nominal + measured), HDR and
    variable-frame-rate. Best-effort — whatever the probe carried."""
    p = probe or {}
    return {k: v for k, v in {
        'fps': p.get('measured_fps') or p.get('fps'),
        'nominal_fps': p.get('nominal_fps'),
        'width': p.get('width'), 'height': p.get('height'),
        'short_side_px': p.get('short_side_px'),
        'rotation': p.get('rotation'),
        'duration_s': p.get('duration') or p.get('duration_s'),
        'frames': p.get('frames'),
        'codec': p.get('codec'), 'color_transfer': p.get('color_transfer'),
        'pix_fmt': p.get('pix_fmt'),
        'bit_depth': (10 if '10' in str(p.get('pix_fmt') or '') else (8 if p.get('pix_fmt') else None)),
        'hdr': p.get('hdr'),
        'variable_frame_rate': p.get('variable_frame_rate'),
        'max_frame_gap_ms': p.get('max_frame_gap_ms'),
        'bytes': p.get('bytes'),
    }.items() if v is not None}


def _probe_clip(src: str) -> dict:
    """Best-effort clip probe for the attempt log, taken BEFORE analysis so even a failed analysis records the
    clip's camera/recording facts (most failures are framing-related). Never raises."""
    info = {}
    try:
        from lanesight_runner.probe import probe as _rprobe
        info = _clip_info(_rprobe(src, check_decoder=False))
    except Exception as pe:
        info = {'probe_error': str(pe)[:200]}
    try:
        info['bytes'] = os.path.getsize(src)
    except Exception:
        pass
    return info


def _snapshot_frames(src: str, n: int = 4, width: int = 480) -> list[dict]:
    """DEC-100: a few small JPEG frames (base64) spread across the clip, stored on a FAILED attempt so the framing
    can be inspected straight from the database (no clip download needed). ~20–30 KB each. Never raises."""
    out = []
    try:
        import base64, cv2
        cap = cv2.VideoCapture(src)
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        fps = cap.get(cv2.CAP_PROP_FPS) or 0
        if total <= 0:
            return out
        for frac in [(i + 0.5) / n for i in range(n)]:
            idx = min(total - 1, int(total * frac))
            cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
            ok, fr = cap.read()
            if not ok:
                continue
            h, w = fr.shape[:2]
            scale = width / max(w, h)
            if scale < 1:
                fr = cv2.resize(fr, (int(w * scale), int(h * scale)))
            ok, buf = cv2.imencode('.jpg', fr, [cv2.IMWRITE_JPEG_QUALITY, 60])
            if ok:
                out.append({'t': round(idx / fps, 2) if fps else None, 'frame': idx,
                            'jpg_b64': base64.b64encode(buf.tobytes()).decode()})
        cap.release()
    except Exception as e:
        out.append({'error': f'{type(e).__name__}: {e}'[:200]})
    return out


def _form_not_isolated(rec) -> dict | None:
    """DEC-100: a form record whose swing events were ALL dropped by the DEC-095 gates (no ball start, top or
    release, no key frames) isn't a result — it's a failure the bowler should see, with the gate numbers."""
    ev = rec.get('events') or {}
    if rec.get('key_frames') or any(ev.get(k) is not None for k in ('E2', 'E4', 'E7')):
        return None
    m = rec.get('metrics') or {}
    def mv(k):
        v = m.get(k)
        return v.get('value') if isinstance(v, dict) else None
    return {'swing_time_s': mv('swing_time'), 'step_count': mv('step_count'), 'view': rec.get('view'),
            'gate': 'DEC-095 ball-start→release 1.3–2.5 s / release within −0.10…+0.15 s of slide stop',
            'events_kept': {k: v for k, v in ev.items() if v is not None}}


def _quality(rec) -> dict | None:
    """Capture-quality + headline-geometry signals from a successful record (DEC-086), so we can correlate
    camera framing with what analysis could measure. Defensive: missing fields are simply omitted."""
    if not isinstance(rec, dict):
        return None
    cq = rec.get('capture_quality') or {}
    m = rec.get('metrics') or {}
    def mv(k):
        v = m.get(k)
        return v.get('value') if isinstance(v, dict) else v
    out = {'far_lane': cq.get('far_lane'), 'capture_reason': cq.get('reason'),
           'entry_board': mv('entry_board'), 'ball_speed': mv('ball_speed'),
           'rev_rate': mv('rev_rate'), 'entry_angle': mv('entry_angle'),
           'n_measured': sum(1 for v in m.values()
                             if (v.get('value') if isinstance(v, dict) else v) is not None) or None}
    for k in ('view', 'status', 'form_version'):     # form clips
        if rec.get(k) is not None:
            out[k] = rec.get(k)
    return {k: v for k, v in out.items() if v is not None} or None


def _analyze_job(shot_id: str, src: str, handed: str | None, user_id: str, session_id: str | None,
                 mode: str = 'shot', is_upload: bool = False, content_hash: str | None = None,
                 client_timings: dict | None = None, clip_storage_path: str | None = None):
    def run(job):
        t0 = time.monotonic()
        if client_timings:                       # DEC-092 P0 (M1): phone-side stage times onto the same row
            job.timings['client'] = client_timings
        out_prefix = str(DATA_ROOT / 'out' / shot_id)
        os.makedirs(os.path.dirname(out_prefix), exist_ok=True)
        store = get_store()
        # Every attempt is logged (success + failure) for failure-rate tracking (DEC-086). Best-effort —
        # a logging failure must never fail the analysis.
        attempt = {'user_id': user_id, 'shot_id': shot_id, 'session_id': session_id,
                   'source': 'upload' if is_upload else 'live', 'capture_mode': mode,
                   'content_hash': content_hash, 'algorithm_version': ALGO_VERSION,
                   'api_revision': os.environ.get('K_REVISION'),
                   # DEC-103: engine provenance. This server path is always 'server'; the on-device engine
                   # (shadow) submits 'ios'. version/build = algorithm_version/api_revision above.
                   'platform': 'server',
                   'env': 'live' if os.environ.get('K_REVISION') else 'dev',
                   # Probe up front so a FAILED analysis still records the clip's camera/recording facts
                   # (resolution, rotation, fps, HDR, VFR) — most failures are framing-related. cold_start
                   # (DEC-092 P0) rides in the clip jsonb so no schema change is needed.
                   'clip': {**_probe_clip(src),
                            'cold_start': (time.monotonic() - _PROCESS_START) < _COLD_START_WINDOW_S}}
        # DEC-100: where the retained clip lives, so any attempt (failed or "succeeded" but empty) can be
        # re-run on the exact bytes the server saw (ops/fetch_clip.py <shot_id>).
        if clip_storage_path:
            attempt['clip']['storage_path'] = clip_storage_path
            attempt['clip']['retained_days'] = clip_retention_days()

        # DEC-092 P0: ~2 s framing precheck. SHADOW by default — record the verdict, never block — until the
        # benchmark shows it rejects zero clips the full pipeline passes. Set LANESIGHT_PRECHECK_ENFORCE=1 to
        # fail fast on a reject (only after that's validated). Ball/shot clips only (form uses the pose path).
        if mode != 'form':
            try:
                from lanesight_core.cv.precheck import precheck as _precheck
                attempt['clip']['precheck'] = _precheck(src)
            except Exception as pe:
                attempt['clip']['precheck'] = {'error': str(pe)[:150]}

        def _log(status, failure=None, diagnostics=None):
            try:
                dur_ms = int((time.monotonic() - t0) * 1000)
                store.log_analysis_attempt({**attempt, 'status': status,
                                            'failure_code': getattr(failure, 'code', None),
                                            'failure_stage': getattr(failure, 'stage', None),
                                            # failure numbers, or (on success) capture-quality + geometry signals
                                            'diagnostics': getattr(failure, 'diagnostics', None) or diagnostics,
                                            'duration_ms': dur_ms,
                                            # DEC-098 §2 (M1): measured compute/egress for cost reporting
                                            'cost': _attempt_cost(dur_ms, attempt.get('clip')),
                                            'step_timings': {k: v for k, v in job.timings.items()}})
            except Exception as le:
                print(f'analysis_attempt log skipped ({le})')

        try:
            # DEC-092 P0: enforce the framing precheck only when explicitly enabled + validated (default off).
            pc = (attempt.get('clip') or {}).get('precheck') or {}
            if mode != 'form' and os.environ.get('LANESIGHT_PRECHECK_ENFORCE') == '1' and pc.get('ok') is False:
                from lanesight_core.failures import AnalysisFailure as _AF
                raise _AF(pc.get('code') or 'LANE_NOT_DETECTED', pc.get('message') or 'precheck rejected framing',
                          stage=pc.get('stage') or 'lane', diagnostics={'precheck': True, **pc})
            if mode == 'form':
                # Form clips (rear / bowler-facing) run the pose pipeline, not the ball CV. Their measurements use
                # source 'lanesight_form', which read_shot_records excludes, so a form shot never feeds the ball
                # L-dev-0 score / Accuracy — hence we skip after_shot_analyzed and return a minimal footer.
                from lanesight_core.form import analyze_form_clip
                from lanesight_core.form.pose import pose_backend
                rec = analyze_form_clip(src, out_prefix=out_prefix, handed=handed, pose_backend=pose_backend)
                rec['shot_id'] = shot_id
                gated = _form_not_isolated(rec)
                if gated:
                    from lanesight_core.failures import AnalysisFailure as _AF
                    raise _AF('FORM_DELIVERY_NOT_ISOLATED', 'every swing event failed the DEC-095 sanity gates',
                              stage='form_pose', diagnostics=gated)
                # Persist key-position frames to Storage so the Form card can serve them later — Cloud Run disk is
                # ephemeral (scale-to-zero). A missing event wrote no file; skip it (never a substitute frame).
                for fkey in (rec.get('key_frames') or []):
                    local = f'{out_prefix}_form_{fkey}.jpg'
                    if os.path.exists(local):
                        try:
                            with open(local, 'rb') as fh:
                                store.storage_upload(_IMAGE_BUCKET, f'frames/{shot_id}_form_{fkey}.jpg',
                                                     fh.read(), 'image/jpeg')
                        except Exception as e:
                            print(f'key-frame upload {fkey} skipped ({e})')
                job.timings['analyze'] = time.monotonic() - t0
                form_footer = engines.after_form_analyzed(store, user_id, session_id, rec,
                                                          analyze_seconds=job.timings['analyze'],
                                                          persist=not is_upload)
                store.save_shot_result(shot_id, rec, {'ok': True, 'mode': 'form'}, algo_version=ALGO_VERSION)
                _log('analyzed', diagnostics=_quality(rec))
                return dict(shot_id=shot_id, mode='form', status=rec.get('status'), view=rec.get('view'),
                            focus=form_footer.get('focus'), key_frames=form_footer.get('key_frames'),
                            footer=form_footer.get('footer'))
            from lanesight_runner.core import analyze_clip
            rec, probe, timings = analyze_clip(src, out_prefix, handed=handed, timings={})
            rec['shot_id'] = shot_id
            for k, v in (timings or {}).items():
                job.timings[k] = v
            job.timings['analyze'] = time.monotonic() - t0
            # Recompute insights with the thrown intent + session history (SHOT_REVIEW #5 / handoff C.4).
            sh = store.get_shot(user_id, shot_id)
            if sh and (sh.get('intent') or sh.get('session_id')):
                pr = rec.get('pins') or {}
                if pr.get('readable'):
                    standing, unc = set(pr.get('standing') or []), set(pr.get('uncertain') or [])
                else:
                    standing, unc = None, set()
                _recompute_insights(store, user_id, sh, rec, standing, unc)
            store.save_shot_result(shot_id, rec, {'ok': True}, algo_version=ALGO_VERSION)
            # Enrich the attempt clip with the richer, validated probe from analysis (measured fps, frames…).
            enriched = _clip_info(probe)
            if enriched:
                attempt['clip'] = {**(attempt.get('clip') or {}), **enriched}
            # Standalone uploads (DEC-055) are analyzed and viewable, but never feed the LaneSight Score,
            # tiers, achievements or findings — so skip the post-shot engine entirely (no footer nudges).
            if is_upload:
                _log('analyzed', diagnostics=_quality(rec))
                return dict(shot_id=shot_id)
            footer = engines.after_shot_analyzed(store, user_id, session_id, rec)
            _log('analyzed', diagnostics=_quality(rec))
            return dict(shot_id=shot_id, **footer)
        except Exception as e:
            # Persist the failure on the shot row (so Lab › Uploads can show it) + log the attempt, then
            # re-raise so the job reports it. Unknown exceptions become a stable INTERNAL_ERROR.
            from lanesight_core.failures import AnalysisFailure
            fail = e if isinstance(e, AnalysisFailure) else \
                AnalysisFailure('INTERNAL_ERROR', f'{type(e).__name__}: {e}'[:500], stage='internal')
            try:
                store.mark_shot_failed(shot_id, fail.code, fail.stage)
            except Exception as me:
                print(f'mark_shot_failed skipped ({me})')
            # DEC-100: keep what we need to diagnose it — snapshot frames of what the camera saw.
            attempt['clip'] = {**(attempt.get('clip') or {}), 'frames': _snapshot_frames(src)}
            _log('failed', failure=fail)
            raise

    return _queue.submit('analyze', run)


# The engine versions that produced the results a piece of feedback is about. core/rules/formula are
# server-authoritative (the client can't be trusted to know them); app_version/app_phase come from the
# build + Beta–Prod toggle and stay as the client sent them (default phase 'dev' for this build).
_FEEDBACK_SOURCES = {'shot_note', 'session_feedback', 'advice_rating', 'form_note', 'general'}


def _stamp_versions(data: dict) -> dict:
    d = dict(data or {})
    d['core_version'] = ALGO_VERSION
    d['rules_version'] = BENCHMARK_VERSION
    d['formula_version'] = SCORE_VERSION
    return d


def _ball_link(store, user, meta):
    """The ball configuration + user ball a shot was thrown with: explicit from the app, else the current ball."""
    cfg, ub = meta.get('ball_configuration_id'), meta.get('user_ball_id')
    if not (cfg and ub) and hasattr(store, 'current_ball'):
        cur = store.current_ball(user) or {}
        cfg = cfg or cur.get('ball_configuration_id')
        ub = ub or cur.get('id')
    return cfg, ub


def _intent_view(intent):
    """Normalize a stored intent into the keys the execution check reads (handoff C.4). execution_check compares
    intent[laydown_board/arrows_board/breakpoint_board] against the shot's actuals; accept either naming
    (arrows_board or board_at_15ft) so the check actually runs instead of being silently skipped."""
    if not intent:
        return None
    iv = {k: v for k, v in dict(intent).items() if v is not None}
    if 'arrows_board' not in iv and iv.get('board_at_15ft') is not None:
        iv['arrows_board'] = iv['board_at_15ft']
    if 'laydown_board' not in iv and iv.get('board_at_0ft') is not None:
        iv['laydown_board'] = iv['board_at_0ft']
    return iv or None


def _shot_view_from_record(rec, standing, uncertain=None):
    """Rebuild the insight input from a stored record's measured values, with the given standing pins. Used to
    recompute insights when the user reports their leave (POST /shots/{id}/pins). standing None = unreadable."""
    M = rec.get('metrics') or {}
    val = lambda k: (M.get(k) or {}).get('value')
    # DEC-094 §5/§6: carry per-metric quality so the recompute path gates moves the same way analysis does.
    quality = {k: {'status': v.get('status'), 'uncertainty': v.get('uncertainty'), 'confidence': v.get('confidence')}
               for k, v in M.items() if isinstance(v, dict)}
    return dict(entry_board=val('entry_board'), entry_angle_deg=val('entry_angle'),
                board_at_15ft=val('arrows_board'), board_at_0ft=val('laydown_board'),
                breakpoint_board=val('breakpoint_board'),
                speed_early=val('speed_early'), speed_late=val('speed_late'),
                trajectory=rec.get('trajectory'), _quality=quality,
                pins_standing=standing, pins_uncertain=(set(uncertain) if uncertain else set()))


def _session_history(store, user_id, sh):
    """Earlier analyzed shots in the same session as light dicts, for the transition read + big-move confirmation."""
    sid = sh.get('session_id')
    if not sid:
        return []
    try:
        rows = store.session_shots(user_id, sid)
    except Exception:
        return []
    hist = []
    for r in rows:
        if r.get('id') == sh.get('id'):
            continue
        eb = (r.get('metrics') or {}).get('entry_board')
        if eb is not None:
            hist.append(dict(entry_board=eb, classification=r.get('classification')))
    return hist


def _recompute_insights(store, user_id, sh, rec, standing, uncertain=None):
    """Recompute strike insights for a stored record with the thrown intent + session history (so the execution
    check and transition read run — the CV pipeline computes neither). Mutates rec['insights'] and returns it."""
    from lanesight_core.insights.adjust import strike_adjustment, suggested_target
    handed = rec.get('handed') or sh.get('handed') or 'R'
    intent = _intent_view(sh.get('intent'))
    sv = _shot_view_from_record(rec, standing, uncertain)
    ins = strike_adjustment(sv, handed, intent=intent, history=_session_history(store, user_id, sh))
    rec['insights'] = ins
    if intent:
        geom = (store.engine_config() or {}).get('line_geometry') if hasattr(store, 'engine_config') else None
        bp_ft = ((rec.get('key_points') or {}).get('breakpoint') or {}).get('z_ft')
        st = suggested_target(ins, intent, geometry=geom, breakpoint_ft=bp_ft)
        if st:
            ins['suggested_target'] = st
    return ins


# ----------------------------------------------------------------- health (no auth)
@app.get('/health')
def health():
    s = settings()
    reachable = s.supabase_reachable()          # None in memory mode, True/False in live mode
    # Fail visibly: a live build that can't reach Supabase is 'degraded' (the dev panel shows it red);
    # we never silently fall back to memory. A build running in memory mode is flagged too.
    if s.mode == 'live':
        status = 'ok' if reachable else 'degraded'
    else:
        status = 'ok'
    return {'status': status, 'supabase_reachable': reachable,
            'versions': {'api': API_VERSION, 'app_compat': APP_COMPAT,
                         'core': ALGO_VERSION, 'rules': BENCHMARK_VERSION, 'formula': SCORE_VERSION},
            'config': {**s.redacted(), 'upload_dedupe': _upload_dedupe_on()}}   # DEC-086 flag (default off)


@app.get('/debug/env')
def debug_env(user=Depends(current_user)):
    """DEC-106 Phase 0: Cloud Run CPU/threading introspection for the perf investigation. Owner-only (no
    secrets, but not public). Confirms whether os.cpu_count() (what numpy/OpenCV/our worker pool size off)
    matches the allocated vCPUs — the suspected oversubscription cause of the Cloud Run vs Mac latency gap."""
    from lanesight_core.owner import OWNER_USER_ID
    if user != OWNER_USER_ID:
        raise HTTPException(403, 'owner only')
    info = {'os_cpu_count': os.cpu_count(),
            'env': {k: os.environ.get(k) for k in
                    ('LANESIGHT_CV_WORKERS', 'OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS',
                     'NUMEXPR_NUM_THREADS', 'VECLIB_MAXIMUM_THREADS', 'K_SERVICE', 'K_REVISION')},
            'execution_environment': os.environ.get('CLOUD_RUN_EXECUTION_ENVIRONMENT')}
    try:
        import cv2
        info['cv2_num_threads'] = cv2.getNumThreads()
    except Exception as e:
        info['cv2'] = str(e)[:120]
    try:
        from lanesight_core.cv._parallel import workers
        info['cv_workers'] = workers()
    except Exception as e:
        info['cv_workers_err'] = str(e)[:120]
    return info


# ----------------------------------------------------------------- auth (email/password, no bearer)
@app.post('/auth/signup')
def auth_signup(body: dict):
    try:
        sess = userauth.signup(body['email'], body['password'])
    except KeyError:
        raise HTTPException(400, 'email and password required')
    except userauth.AuthError as e:
        raise HTTPException(e.status if 400 <= e.status < 600 else 400, str(e.body)[:300])
    get_store().put_profile(sess['user_id'], {})      # ensure a profiles row so session/shot FKs hold
    return sess

@app.post('/auth/signin')
def auth_signin(body: dict):
    try:
        return userauth.signin(body['email'], body['password'])
    except KeyError:
        raise HTTPException(400, 'email and password required')
    except userauth.AuthError:
        raise HTTPException(401, 'invalid email or password')

@app.post('/auth/refresh')
def auth_refresh(body: dict):
    try:
        return userauth.refresh(body['refresh_token'])
    except (KeyError, userauth.AuthError):
        raise HTTPException(401, 'could not refresh session')


# ----------------------------------------------------------------- sessions
@app.post('/sessions')
def create_session(body: dict | None = None, user=Depends(current_user)):
    return get_store().create_session(user, body or {})

@app.get('/sessions')
def list_sessions(user=Depends(current_user)):
    return get_store().list_sessions(user)

@app.get('/sessions/{sid}')
def get_session(sid: str, user=Depends(current_user)):
    s = get_store().get_session(user, sid)
    if not s:
        raise HTTPException(404, 'session not found')
    return s

@app.post('/sessions/{sid}/end')
def end_session(sid: str, user=Depends(current_user)):
    store = get_store()
    summary = store.end_session(user, sid)
    if not summary:
        raise HTTPException(404, 'session not found')
    snap, tier, ach = engines.at_session_end(store, user, sid)
    summary['score'] = {'eligible': snap['eligible'], 'score': snap['score'], 'tier': snap['tier']}
    summary['tier_event'] = tier.get('event')
    summary['personal_best'] = tier.get('personal_best')
    # extra unlocks batched into the summary (SCORE_TIERS §6)
    summary['unlocked'] = ach['unlocked']
    summary['notifications'] = store.list_notifications(user, undelivered=True)
    return summary


@app.get('/sessions/{sid}/summary')
def session_summary(sid: str, user=Depends(current_user)):
    """Re-openable session summary (MVP-07): per-metric averages ± spread + range, consistency, and a
    'vs your typical' block from recent comparable sessions (same oil pattern). Typical stays 'building' until
    3 comparable sessions exist. NOTE: typical relies on list_sessions, which is not yet DB-backed in PgStore
    (see the session-persistence follow-up), so on a cold Cloud Run instance it reports 'building' until the
    session lifecycle is persisted — graceful, never wrong."""
    store = get_store()
    sess = store.get_session(user, sid)
    if not sess:
        raise HTTPException(404, 'session not found')
    from lanesight_core.insights import session as si
    records = store.session_records(user, sid)
    pattern = sess.get('oil_pattern_id')
    others = [s for s in store.list_sessions(user)
              if s.get('id') != sid and s.get('oil_pattern_id') == pattern]
    others.sort(key=lambda s: s.get('started_at') or 0, reverse=True)
    others = others[:5]
    MIN_COMPARABLE = 3
    if len(others) < MIN_COMPARABLE:
        typical = {'status': 'building', 'n_sessions': len(others), 'need': MIN_COMPARABLE}
    else:
        agg: dict = {}
        for s in others:
            for metric, a in si.summary(store.session_records(user, s['id'])).items():
                agg.setdefault(metric, []).append(a['mean'])
        typical = {'status': 'ok', 'n_sessions': len(others),
                   'metrics': {m: round(sum(v) / len(v), 2) for m, v in agg.items() if v}}
    # Early-vs-late split (first N vs last N measured shots) for the session-summary "Early vs late" block.
    def _early_late(metric, n=8):
        vals = si._vals(records, metric)                 # ordered, only 'ok'/'calibrated_estimate'
        if len(vals) < 4:
            return None
        k = min(n, len(vals) // 2)
        early, late = vals[:k], vals[-k:]
        em, lm = sum(early) / len(early), sum(late) / len(late)
        return {'early': round(em, 2), 'late': round(lm, 2), 'delta': round(lm - em, 2),
                'n_early': len(early), 'n_late': len(late)}
    early_vs_late = {m: _early_late(m) for m in ('ball_speed', 'rev_rate', 'entry_angle', 'breakpoint_board')}
    early_vs_late = {k: v for k, v in early_vs_late.items() if v}
    # Session focus (the recurring issue across the session's shots) — reuses each shot's own rec copy.
    focus = si.next_focus([{'record': r} for r in records], lookback=len(records) or 1)

    return {'session_id': sid, 'n_shots': len(records), 'oil_pattern_id': pattern,
            'metrics': si.summary(records), 'consistency': si.consistency(records), 'typical': typical,
            'early_vs_late': early_vs_late, 'focus': focus}


@app.get('/sessions/{sid}/form-summary')
def form_session_summary(sid: str, user=Depends(current_user)):
    """Form-session analytics (v3.7 Active Session·Form 464:7377 / Form session summary 430:5744):
    repeatability (mean ± spread per form metric across the session's deliveries), early-vs-late, a takeaway,
    and the delivery list. Form is diagnostic ONLY — never part of the LaneSight (ball) score. Every value is
    read from each delivery's MEASURED form record (no fabrication); a metric with too few measured deliveries
    reads 'building'."""
    import statistics as _stats
    from collections import Counter
    store = get_store()
    sess = store.get_session(user, sid)
    if not sess:
        raise HTTPException(404, 'session not found')
    records = store.session_records(user, sid)      # ordered oldest→newest form records

    def _metric(rec, key):                           # metrics[key].value, measured only
        return engines._form_val(rec, key)
    def _t4(rec):                                    # release-timing offset (s) vs ideal window
        t = (rec.get('timing_checkpoints') or {}).get('T4') or {}
        return t.get('offset') if t.get('status') == 'ok' else None
    def _t2(rec):                                    # ball-start step index
        t = (rec.get('timing_checkpoints') or {}).get('T2') or {}
        return t.get('offset') if t.get('status') == 'ok' else None
    def _spine(rec):                                 # spine tilt (deg), measured/best-effort
        p = (rec.get('measured_positions') or {}).get('spine_tilt') or {}
        return p.get('value') if p.get('status') in ('ok', 'best_effort', 'calibrated_estimate') else None
    def _series(fn):
        return [v for v in (fn(r) for r in records) if v is not None]

    # A metric is "drifting" when the first-half → second-half mean shifts by more than `trend_min`
    # (a directional trend across the session), not merely when within-session scatter is high.
    def _first_last(vals, n=4):
        if len(vals) < 4:
            return None
        k = min(n, len(vals) // 2)
        early, late = vals[:k], vals[-k:]
        return sum(early) / len(early), sum(late) / len(late)

    # (key, label, unit, extractor, best_effort, trend_min for 'drifting' | None)
    SPECS = [
        ('approach_time',  'Approach time',  's',    lambda r: _metric(r, 'approach_time'), False, 0.08),
        ('release_timing', 'Release timing', 's',    _t4,                                   False, 0.03),
        ('ball_start',     'Ball start',     'step', _t2,                                    False, None),
        ('swing_time',     'Swing time',     's',    lambda r: _metric(r, 'swing_time'),    False, 0.05),
        ('spine_tilt',     'Spine tilt',     'deg',  _spine,                                 True,  None),
    ]
    repeatability, drifting = [], []
    for key, label, unit, fn, best_effort, trend_min in SPECS:
        vals = _series(fn)
        if not vals:
            repeatability.append({'key': key, 'label': label, 'unit': unit, 'status': 'building',
                                  'n': 0, 'mean': None, 'spread': None, 'best_effort': best_effort, 'display': '—'})
            continue
        mean = round(sum(vals) / len(vals), 3)
        spread = round(_stats.pstdev(vals), 3) if len(vals) > 1 else 0.0
        if key == 'ball_start':
            steps = [round(v) for v in vals]
            mode, cnt = Counter(steps).most_common(1)[0]
            status = 'steady' if cnt >= max(2, (len(steps) * 3) // 4) else 'varied'
            repeatability.append({'key': key, 'label': label, 'unit': unit, 'status': status, 'n': len(vals),
                                  'mode': mode, 'count': cnt, 'best_effort': False,
                                  'display': f'Step {mode} on {cnt} of {len(steps)}'})
            continue
        fl = _first_last(vals)
        drift = bool(fl and trend_min is not None and abs(fl[1] - fl[0]) >= trend_min)
        status = 'best_effort' if best_effort else ('drifting' if drift else 'steady')
        if unit == 's':
            display = f'{mean:.2f} s ± {spread:.2f}'
        elif unit == 'deg':
            display = f'{round(mean)}° ± {round(spread)}°'
        else:
            display = f'{mean} ± {spread}'
        repeatability.append({'key': key, 'label': label, 'unit': unit, 'status': status, 'n': len(vals),
                              'mean': mean, 'spread': spread, 'best_effort': best_effort, 'display': display})
        if status == 'drifting':
            drifting.append(label.lower())

    def _early_late(fn, n=4):
        vals = _series(fn)
        if len(vals) < 4:
            return None
        k = min(n, len(vals) // 2)
        early, late = vals[:k], vals[-k:]
        em, lm = sum(early) / len(early), sum(late) / len(late)
        return {'early': round(em, 3), 'late': round(lm, 3), 'delta': round(lm - em, 3),
                'n_early': k, 'n_late': k, 'series': [round(v, 3) for v in vals]}
    evl = {}
    for key, fn in (('release_timing', _t4), ('approach_time', lambda r: _metric(r, 'approach_time'))):
        r = _early_late(fn)
        if r:
            evl[key] = r

    deliveries = []
    for i, rec in enumerate(records):
        deliveries.append({'seq': i + 1, 'release_offset': _t4(rec),
                           'swing_total': _metric(rec, 'swing_time'), 'view': rec.get('view')})
    deliveries.reverse()                             # newest first for the list

    view = next((r.get('view') for r in records if r.get('view') and r.get('view') != 'unknown'), None)
    rel = evl.get('release_timing')
    takeaway = None
    if rel and abs(rel['delta']) >= 0.03:
        direction = 'late' if rel['delta'] > 0 else 'early'
        rest = 'your approach time stayed steady' if 'approach time' not in drifting else 'the rest held together'
        takeaway = {'text': f'Your release timing drifted {direction} through the session. And {rest}.',
                    'drill': 'Drill for next practice: slide-and-release — feel the slide foot stop, then let the ball come through.'}
    elif repeatability and all(r.get('status') in ('steady', 'best_effort', 'building') for r in repeatability) \
            and any(r.get('n') for r in repeatability):
        takeaway = {'text': 'Your delivery repeated well across the session — timing and positions held steady.',
                    'drill': 'Keep grooving this rhythm; small, consistent reps build the pattern.'}

    ended = sess.get('ended_at')
    return {'session_id': sid, 'mode': 'form', 'view': view, 'n_deliveries': len(records),
            'ended_at': ended, 'in_progress': ended is None,
            'repeatability': repeatability, 'early_vs_late': evl, 'takeaway': takeaway, 'deliveries': deliveries,
            'note': 'Compared with your baseline from Profile. Form stats are diagnostic and aren’t part of your LaneSight Score.'}


# ----------------------------------------------------------------- shots
@app.post('/sessions/{sid}/shots')
async def create_shot(sid: str, file: UploadFile = File(...), metadata: str = Form('{}'),
                      user=Depends(current_user)):
    s = get_store().get_session(user, sid)
    if not s:
        raise HTTPException(404, 'session not found')
    meta = json.loads(metadata or '{}')
    store = get_store()
    cfg, ub = _ball_link(store, user, meta)
    shot = store.create_shot(user, sid, {'intent': meta.get('intent'), 'capture_mode': meta.get('capture_mode'),
                                         'source': meta.get('source', 'live'), 'sensor_used': meta.get('sensor_used'),
                                         'sensor_id': meta.get('sensor_id'), 'handed': meta.get('handed'),
                                         'ball_configuration_id': cfg, 'user_ball_id': ub, 'oil_pattern_id': meta.get('oil_pattern_id')})
    dest = DATA_ROOT / 'sessions' / sid
    dest.mkdir(parents=True, exist_ok=True)
    path = dest / f"{shot['id']}.mov"
    with open(path, 'wb') as f:
        f.write(await file.read())
    job = _analyze_job(shot['id'], str(path), meta.get('handed'), user, sid,
                       mode=(meta.get('capture_mode') or 'shot'))
    return {'shot_id': shot['id'], 'job_id': job.id}

@app.get('/jobs/{job_id}')
def get_job(job_id: str, user=Depends(current_user)):
    job = _queue.get(job_id)
    if not job:
        raise HTTPException(404, 'job not found')
    return job.public()

def _flat_metrics(m: dict) -> dict:
    """Flatten a record's metrics ({k:{value}} or {k:v}) to {k: value}."""
    out = {}
    for k, v in (m or {}).items():
        out[k] = v.get('value') if isinstance(v, dict) else v
    return out


def _shot_card_enrich(store, user, sh: dict) -> dict:
    """DEC-088/090: add the shot-card fields to a BALL shot's record — path_fit (from the already-smoothed
    trajectory), impact_energy_j (DEC-024), baseline, and insights.throw/lane/coach (the coach matrix).
    Best-effort + additive; a form shot or any error leaves the record untouched (older clients ignore the
    new keys). Computed at read time so the baseline is always current."""
    try:
        rec = sh.get('record') or {}
        if not rec or rec.get('form_version') or not rec.get('metrics'):
            return sh          # form shots / empty records have no ball lane read
        m = _flat_metrics(rec.get('metrics'))
        # path_fit: the trajectory is already LOESS-smoothed in lane coords; expose it + the measured extent.
        tr = rec.get('trajectory') or {}
        sm = tr.get('smoothed') or []
        if sm:
            zs = [p['z_ft'] for p in sm if p.get('z_ft') is not None]
            rec['path_fit'] = {'points': sm, 'measured_extent_ft': [min(zs), max(zs)] if zs else None}
        # Power / impact energy (DEC-024): pocket speed + rev + ball weight; best-effort, labeled.
        from lanesight_core import power
        pw = power.power(engines._weight_lb(store, user), m.get('speed_late') or m.get('ball_speed'),
                         m.get('rev_rate'))
        rec['impact_energy_j'] = pw.get('energy_j')
        rec['power'] = pw
        # Coach: classify throw vs the bowler's normal (prior LIVE shots) + lane vs the pocket.
        from lanesight_core.insights import coach as _coach
        prior = []
        for p in store.shot_points(user):
            if p.get('shot_id') == sh.get('id'):
                continue
            pm = _flat_metrics((p.get('record') or {}).get('metrics'))
            prior.append({'ball_speed': pm.get('ball_speed'), 'rev_rate': pm.get('rev_rate'),
                          'arrows_board': pm.get('arrows_board')})
        intent = sh.get('intent') or {}
        # Target line for the coach + DEC-031 Accuracy: carry both the arrows and breakpoint intent (Accuracy
        # uses both; breakpoint is dropped honestly downstream when it isn't measured from this camera).
        target = None
        if intent.get('arrows_board') is not None or intent.get('breakpoint_board') is not None:
            target = {'arrows_board': intent.get('arrows_board'),
                      'breakpoint_board': intent.get('breakpoint_board')}
        rec0 = ((rec.get('insights') or {}).get('recommendations') or [{}])[0] or {}
        far = 'not_read' if (rec.get('capture_quality') or {}).get('far_lane') in ('limited', 'not_read') else None
        _mq = rec.get('metrics') or {}
        quality = {k: {'status': v.get('status'), 'uncertainty': v.get('uncertainty'), 'confidence': v.get('confidence')}
                   for k, v in _mq.items() if isinstance(v, dict)}       # DEC-094 §5/§6
        cb = _coach.build(m, rec.get('key_points'), prior, target=target, recommendation=rec0, far_lane=far, quality=quality)
        ins = rec.setdefault('insights', {})
        ins['throw'], ins['lane'], ins['coach'] = cb['throw'], cb['lane'], cb['coach']
        rec['baseline'] = cb['baseline']
        # Speed vs the bowler's OWN baseline (≥20 prior shots): a speed far from their norm is suspect even when
        # internally consistent — mark it low_confidence, never a silent 'ok' (2026-10-29). Serve-time only.
        base_sp = (cb['baseline'] or {}).get('speed'); base_n = (cb['baseline'] or {}).get('n') or 0
        spm = _mq.get('ball_speed') if isinstance(_mq.get('ball_speed'), dict) else None
        if base_sp and base_n >= 20 and spm and spm.get('value') is not None and spm.get('status') == 'ok' \
           and abs(spm['value'] - base_sp) > max(3.0, 0.25 * base_sp):
            spm['status'] = 'low_confidence'
            spm['confidence'] = min(spm.get('confidence') or 1.0, 0.4)
            spm['note'] = ((spm.get('note') + ' ') if spm.get('note') else '') + \
                f"{spm['value']:.1f} mph is far from your {base_sp:.1f} mph average ({base_n} shots) — read with caution."
    except Exception as e:
        print(f'shot-card enrich skipped ({type(e).__name__}: {e})')
    return sh


@app.get('/shots/{shot_id}')
def get_shot(shot_id: str, user=Depends(current_user)):
    store = get_store()
    sh = store.get_shot(user, shot_id)
    if not sh:
        raise HTTPException(404, 'shot not found')
    sh = _shot_card_enrich(store, user, sh)
    # DEC-097: the shot card shows the ball used (and the oil it was thrown on), resolved per shot.
    try:
        ball_names, oil_names = store._ball_oil_names(user)
        sh['ball_name'] = ball_names.get(sh.get('user_ball_id') or sh.get('ball_configuration_id'))
        sh['oil_name'] = oil_names.get(sh.get('oil_pattern_id'))
    except Exception as e:
        print(f'shot ball/oil name resolve skipped ({type(e).__name__}: {e})')
    return sh

@app.patch('/shots/{shot_id}')
def patch_shot(shot_id: str, body: dict, user=Depends(current_user)):
    store = get_store()
    patch = dict(body or {})
    # Advice 👍/👎 on next-shot advice is carried on the shot patch; route it into the retained feedback
    # store (DEC-059) as an 'advice_rating' row rather than mutating the measured shot. The outcome tables
    # keep their measurement role; this is write-and-keep and never changes runtime behavior.
    thumbs = patch.pop('thumbs', None)
    advice_text = patch.pop('advice_text', None)
    sh = store.get_shot(user, shot_id)
    if not sh:
        raise HTTPException(404, 'shot not found')
    if thumbs in ('up', 'down'):
        rec = sh.get('record') or {}
        store.add_feedback(user, _stamp_versions({
            'source': 'advice_rating', 'shot_id': shot_id, 'session_id': sh.get('session_id'),
            'recommendation_id': patch.pop('recommendation_id', None),
            'capture_mode': sh.get('capture_mode'), 'is_upload': sh.get('source') == 'upload',
            'thumbs': thumbs, 'text': advice_text,
            'app_phase': patch.pop('app_phase', None), 'app_version': patch.pop('app_version', None),
            'context': {'advice': (rec.get('insights') or {}).get('suggested_target'),
                        'intent': sh.get('intent')}}))
    if patch:
        sh = store.patch_shot(user, shot_id, patch)
    return sh


# Key-position stills for the Form screen's KEY POSITIONS row. Owner-scoped; only frames the pose exported
# exist on disk (recorded in the form record's key_frames), so a missing frame is an honest 404.
_FORM_FRAME_KEYS = {'ball_start', 'end_pushaway', 'top_of_swing', 'release'}   # DEC-057 key positions


@app.get('/shots/{shot_id}/frame/{key}')
def get_shot_frame(shot_id: str, key: str, user=Depends(current_user)):
    if key not in _FORM_FRAME_KEYS:
        raise HTTPException(404, 'unknown frame key')
    if not get_store().get_shot(user, shot_id):        # owner-scoped
        raise HTTPException(404, 'shot not found')
    try:                                               # durable in Storage (Cloud Run disk is ephemeral)
        data = get_store().storage_download(_IMAGE_BUCKET, f'frames/{shot_id}_form_{key}.jpg')
    except Exception:
        raise HTTPException(404, 'frame not available')
    return Response(content=data, media_type='image/jpeg')


@app.post('/shots/{shot_id}/pins')
def report_pins(shot_id: str, body: dict, user=Depends(current_user)):
    """The user reports their actual leave when the deck couldn't be read (handoff C.2). Body:
    {strike: bool} | {pins: [int 1..10]} | {leave: "split"|"other"}. Stores the leave as source 'user',
    recomputes insights, and returns the updated shot so the card re-renders from the new state."""
    store = get_store()
    sh = store.get_shot(user, shot_id)
    if not sh:
        raise HTTPException(404, 'shot not found')
    rec = sh.get('record')
    if not rec:
        raise HTTPException(409, 'shot not analyzed yet')
    b = body or {}
    leave = b.get('leave')
    if b.get('strike'):
        standing = set()                                   # strike: nothing standing
    elif b.get('pins'):
        try:
            standing = {int(p) for p in b['pins']}
        except (TypeError, ValueError):
            raise HTTPException(422, 'pins must be integers 1..10')
        if not standing <= set(range(1, 11)):
            raise HTTPException(422, 'pins must be 1..10')
    else:
        standing = None                                    # a reported leave (split/other) without specific pins
    ins = _recompute_insights(store, user, sh, rec, standing)
    if standing is None and leave in ('split', 'other'):
        ins['note'] = f"You reported a {leave}. Pick the standing pins to get a line move."
    rec['pins'] = dict(rec.get('pins') or {}, readable=True, source='user', unread_reason=None,
                       strike=(standing == set()), leave_type=leave, uncertain=[],
                       standing=(sorted(standing) if standing is not None else None),
                       pins_down_min=(10 - len(standing)) if standing is not None else None,
                       pins_down_max=(10 - len(standing)) if standing is not None else None)
    store.save_shot_result(shot_id, rec, sh.get('result') or {'ok': True})
    return store.get_shot(user, shot_id)


# ----------------------------------------------------------------- spot check (advisory, never blocks)
@app.post('/spot-check')
def do_spot_check(body: dict | None = None, user=Depends(current_user)):
    return spot_check((body or {}).get('framing', {}))


# ----------------------------------------------------------------- score
_SCORE_PART_KEYS = ('s_perf', 'a_acc', 'c_cons', 'p_power')


def _with_part_deltas(store, user, snap, window_days=30):
    """DEC-083: attach `parts_delta_30d` — each part's change vs the most recent snapshot at least
    `window_days` old. Only parts with a value in BOTH the current and reference snapshot get a delta;
    the rest are omitted (the app renders 'New'). Needs real history — nothing is fabricated."""
    if not snap:
        return snap
    try:
        hist = sorted(store.score_history(user), key=lambda s: s.get('computed_at') or 0)
    except Exception:
        hist = []
    deltas = {}
    if hist:
        cutoff = time.time() - window_days * 86400
        older = [s for s in hist if (s.get('computed_at') or 0) <= cutoff]
        ref = older[-1] if older else None
        if ref:
            for k in _SCORE_PART_KEYS:
                cur, old = snap.get(k), ref.get(k)
                if cur is not None and old is not None:
                    deltas[k] = round(cur - old, 1)
    return {**snap, 'parts_delta_30d': deltas}


@app.get('/me/score')
def me_score(user=Depends(current_user)):
    store = get_store()
    snap = store.latest_score(user) or engines.recompute_score(store, user, trigger='shot')
    return _with_part_deltas(store, user, snap)


@app.get('/me/score/breakdown')
def me_score_breakdown(user=Depends(current_user)):
    """Score-parts detail for the Stats · Score screen (v3.7). Returns the already-computed component
    inputs behind each part score — pocket %/angle % (Performance), avg board miss + target coverage
    (Accuracy), per-checkpoint spreads (Consistency), and the raw power means (Power). Recomputes purely
    over the 90-day window (no persistence / side effects); nothing is fabricated — a part with too few
    measured shots reports null, which the UI renders as '—'."""
    from lanesight_core.score import compute as score_compute
    from lanesight_core.insights import session as si
    store = get_store()
    params = store.score_formula_params()
    records, intents, handed = store.read_shot_records(user, window_days=params.get('window_days'))
    snap = score_compute(records, intents=intents, params=params, handed=handed,
                         weight_lb=engines._weight_lb(store, user))
    comps = snap.get('components') or {}
    S, A, C, P = (comps.get(k) or {} for k in ('s_perf', 'a_acc', 'c_cons', 'p_power'))
    per = A.get('per_shot') or []
    arrow_errs = [p['arrow_err'] for p in per if p.get('arrow_err') is not None]
    bp_errs = [p['bp_err'] for p in per if p.get('bp_err') is not None]
    sm = si.summary(records)
    def _mean(m): return (sm.get(m) or {}).get('mean')
    return {
        'eligible': snap.get('eligible'), 'score': snap.get('score'), 'tier': snap.get('tier'),
        'performance': {'value': S.get('value'), 'pocket_pct': S.get('pocket_pct'),
                        'angle_pct': S.get('angle_pct')},
        'accuracy': {'value': A.get('value'),
                     'avg_arrow_miss': round(sum(arrow_errs) / len(arrow_errs), 1) if arrow_errs else None,
                     'avg_bp_miss': round(sum(bp_errs) / len(bp_errs), 1) if bp_errs else None,
                     'n_with_target': A.get('n', 0), 'n_total': len(records)},
        'consistency': {'value': C.get('value'), 'spreads': C.get('components') or {}},
        'power': {'value': P.get('value'), 'entry_speed': _mean('ball_speed'),
                  'rev_rate': _mean('rev_rate'), 'entry_angle': _mean('entry_angle')},
    }


@app.get('/me/notify')
def get_notify(user=Depends(current_user)):
    """DEC-084: the user's launch-notify flags (currently just coaching_launch)."""
    return get_store().get_notify_prefs(user)


@app.put('/me/notify')
def put_notify(body: dict, user=Depends(current_user)):
    """DEC-084: record "notify me when Coaching launches". Idempotent; returns the current flags."""
    store = get_store()
    if (body or {}).get('coaching_launch'):
        store.set_notify_pref(user, 'coaching_launch', True)
    return store.get_notify_prefs(user)


@app.get('/me/last-setup')
def me_last_setup(user=Depends(current_user)):
    """Prefill Setup with the last-used ball, oil pattern and target (MVP-09). Nulls for a new user."""
    return get_store().last_setup(user)


@app.get('/me/focus')
def me_focus(user=Depends(current_user)):
    """Home 'next focus' (MVP-12): the single recurring issue across recent shots, or a building / keep-repeating
    state. Reuses each shot's own recommendation copy — one focus at a time."""
    from lanesight_core.insights import session as si
    return si.next_focus(get_store().shot_points(user))

@app.get('/me/score/history')
def me_score_history(user=Depends(current_user)):
    return get_store().score_history(user)


# ----------------------------------------------------------------- feedback + export
# One retained feedback store (DEC-059). Write-and-keep: nothing here is read to change a measurement,
# rule, score or advice, and there is NO client delete — removing feedback is an owner action only.
@app.post('/sessions/{sid}/feedback')
def feedback(sid: str, body: dict, user=Depends(current_user)):
    if not get_store().get_session(user, sid):
        raise HTTPException(404, 'session not found')
    # keep the session-end submission working; routing into the feedback table happens in the store.
    return get_store().save_feedback(user, sid, _stamp_versions(body or {}))

@app.post('/feedback')
def submit_feedback(body: dict, user=Depends(current_user)):
    """Submit a feedback row for any source (shot_note, advice_rating, form_note, general). Shot notes
    autosave: resend with the same `id` to update the row. Links to shot/session are optional and are
    kept only while the source exists; the row itself is retained if they're deleted."""
    store = get_store()
    data = _stamp_versions(body or {})
    src = data.get('source') or 'general'
    if src not in _FEEDBACK_SOURCES:
        raise HTTPException(400, f'unknown feedback source {src!r}')
    data['source'] = src
    # defense in depth (the service role bypasses RLS): a linked shot/session must belong to the caller.
    if data.get('shot_id') and not store.get_shot(user, data['shot_id']):
        raise HTTPException(404, 'shot not found')
    if data.get('session_id') and not store.get_session(user, data['session_id']):
        raise HTTPException(404, 'session not found')
    return store.add_feedback(user, data)

@app.post('/events')
def post_events(body: dict = Body(...), user=Depends(current_user)):
    """DEC-098 §2 (M3): ingest consent-aware product events. Body: {"events": [{event_name, occurred_at,
    client_event_id, app_version, feature, flow_step, status, props}, ...]}. Unknown event_names are dropped
    (schema registry); the store pseudonymises user_id -> user_ref and dedups on client_event_id. Never
    accepts raw PII — props should already be masked by the client (strategy §4 exclusions)."""
    events = body.get('events') if isinstance(body, dict) else None
    if not isinstance(events, list):
        raise HTTPException(400, 'events must be a list')
    env = 'live' if os.environ.get('K_REVISION') else 'dev'
    rows = []
    for e in events[:200]:
        if not isinstance(e, dict):
            continue
        name = (e.get('event_name') or '').strip()
        if name not in _PRODUCT_EVENTS:
            continue
        rows.append({'event_name': name, 'user_id': user, 'env': env,
                     'occurred_at': e.get('occurred_at'), 'app_version': e.get('app_version'),
                     'feature': e.get('feature'), 'flow_step': e.get('flow_step'),
                     'status': e.get('status'), 'props': e.get('props'),
                     'client_event_id': e.get('client_event_id')})
    inserted = get_store().log_events(rows)
    return {'received': len(events), 'accepted': inserted}

@app.get('/sessions/{sid}/export.csv')
def export_csv(sid: str, user=Depends(current_user)):
    store = get_store()
    if not store.get_session(user, sid):
        raise HTTPException(404, 'session not found')
    csv_text = session_csv(store.shots_for_session(sid), store.feedback.get(sid, []))
    return Response(csv_text, media_type='text/csv')


# ----------------------------------------------------------------- profile / sensors / catalog / oil
@app.get('/me/profile')
def get_profile(user=Depends(current_user)):
    return get_store().get_profile(user) or {'user_id': user}

@app.put('/me/profile')
def put_profile(body: dict, user=Depends(current_user)):
    store = get_store()
    existing = store.get_profile(user) or {}
    try:
        # DEC-087: reject bad input (phone / grip / PAP / DOB + 13+ gate), never clamp. The 400 detail is
        # {field, message} so the app can show the reason inline on the field and keep the user's input.
        validate_profile_patch(body or {}, existing)
    except ProfileValidationError as e:
        raise HTTPException(400, {'field': e.field, 'message': e.message})
    return store.put_profile(user, body or {})


@app.put('/me/email')
def put_email(body: dict, authorization: str | None = Header(default=None), user=Depends(current_user)):
    """DEC-087: start an email change via Supabase Auth. GoTrue emails a confirmation link; the address
    does NOT change until the user confirms, and email is never written into `profiles`."""
    email = str((body or {}).get('email') or '').strip()
    if '@' not in email or email.startswith('@') or email.endswith('@'):
        raise HTTPException(400, {'field': 'email', 'message': 'Enter a valid email address.'})
    if not authorization or not authorization.startswith('Bearer '):
        raise HTTPException(401, 'missing bearer token')
    try:
        st, resp = userauth.update_email(authorization[7:], email)
    except userauth.AuthError as e:
        raise HTTPException(e.status if 400 <= e.status < 600 else 400, str(e.body)[:300])
    if st >= 400:
        raise HTTPException(st if 400 <= st < 600 else 400, str(resp)[:300])
    return {'status': 'confirmation_sent', 'email_pending': email,
            'message': 'Check your new email to confirm the change.'}


# ----------------------------------------------------------------- profile photo (handoff G)
_AVATAR_MAX_BYTES = 10 * 1024 * 1024
# Durable image bucket (avatars, Form key-position frames). Cloud Run disk is ephemeral (scale-to-zero), so
# images that outlive one request MUST live in Supabase Storage, not DATA_ROOT. Private; service-role access.
_IMAGE_BUCKET = 'shot-images'


def _iso_now():
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat()


def _process_avatar(data: bytes) -> bytes:
    """Decode (Pillow; HEIC/HEIF falls back to the Mac host's `sips`), apply EXIF orientation then STRIP all
    metadata (incl. GPS), centre-crop square, 512 px, re-encode JPEG. Raises ValueError if unreadable."""
    from io import BytesIO
    from PIL import Image, ImageOps
    try:
        img = Image.open(BytesIO(data)); img.load()
    except Exception:
        import subprocess, tempfile, os as _os
        with tempfile.TemporaryDirectory() as td:          # HEIC (no pillow-heif): transcode with sips
            src, dst = _os.path.join(td, 'in'), _os.path.join(td, 'out.jpg')
            with open(src, 'wb') as f:
                f.write(data)
            r = subprocess.run(['sips', '-s', 'format', 'jpeg', src, '--out', dst], capture_output=True)
            if r.returncode != 0 or not _os.path.exists(dst):
                raise ValueError('unsupported image format')
            img = Image.open(dst); img.load()
    img = ImageOps.exif_transpose(img).convert('RGB')       # honor orientation, drop alpha
    s = min(img.size); left = (img.width - s) // 2; top = (img.height - s) // 2
    img = img.crop((left, top, left + s, top + s)).resize((512, 512), Image.LANCZOS)
    out = BytesIO()
    img.save(out, format='JPEG', quality=85)                # no exif= argument -> metadata/GPS stripped
    return out.getvalue()


@app.put('/me/avatar')
async def put_avatar(file: UploadFile = File(...), user=Depends(current_user)):
    data = await file.read()
    if len(data) > _AVATAR_MAX_BYTES:
        raise HTTPException(413, 'image too large (max 10 MB)')
    try:
        jpeg = _process_avatar(data)
    except ValueError:
        raise HTTPException(415, 'unsupported image — send HEIC, JPEG or PNG')
    rel = f'avatars/{user}.jpg'
    get_store().storage_upload(_IMAGE_BUCKET, rel, jpeg, 'image/jpeg')
    ts = _iso_now()
    get_store().set_avatar(user, rel, ts)
    return {'has_avatar': True, 'avatar_updated_at': ts}


@app.get('/me/avatar')
def get_avatar(user=Depends(current_user)):
    path = (get_store().get_avatar(user) or {}).get('avatar_path')
    if not path:
        raise HTTPException(404, 'no avatar set')
    try:
        data = get_store().storage_download(_IMAGE_BUCKET, path)
    except Exception:
        raise HTTPException(404, 'no avatar set')
    return Response(content=data, media_type='image/jpeg')


@app.delete('/me/avatar')
def delete_avatar(user=Depends(current_user)):
    store = get_store()
    path = (store.get_avatar(user) or {}).get('avatar_path')
    if path:
        store.storage_delete(_IMAGE_BUCKET, path)
    store.clear_avatar(user)
    return {'has_avatar': False}


@app.get('/me/sensors')
def list_sensors(user=Depends(current_user)):
    return get_store().list_sensors(user)

@app.post('/me/sensors')
def add_sensor(body: dict, user=Depends(current_user)):
    return get_store().add_sensor(user, body or {})      # user-entered name + default flag (no brand names, DEC-049)

@app.delete('/me/sensors/{sensor_id}')
def delete_sensor(sensor_id: str, user=Depends(current_user)):
    return {'deleted': get_store().delete_sensor(user, sensor_id)}

@app.get('/catalog/balls')
def catalog_balls(q: str | None = None, user=Depends(current_user)):
    return get_store().catalog_balls(q)

@app.get('/oil-patterns')
def oil_patterns(user=Depends(current_user)):
    return get_store().oil_patterns()

@app.get('/me/arsenal')
def get_arsenal(user=Depends(current_user)):
    return get_store().list_arsenal(user)

@app.post('/me/arsenal')
def add_ball(body: dict, user=Depends(current_user)):
    return get_store().add_ball(user, body or {})

@app.patch('/me/arsenal/{ball_id}')
def update_ball(ball_id: str, body: dict, user=Depends(current_user)):
    row = get_store().update_ball(user, ball_id, body or {})   # set current, layout, surface, weight, nickname, retire
    if not row:
        raise HTTPException(404, 'ball not found')
    return row

@app.post('/me/arsenal/{ball_id}/surface')
def add_surface(ball_id: str, body: dict | None = None, user=Depends(current_user)):
    row = get_store().add_surface_event(user, ball_id, body or {})
    if not row:
        raise HTTPException(404, 'ball not found')
    return row


# ----------------------------------------------------------------- live session screen
@app.get('/sessions/{sid}/shots')
def session_shots(sid: str, user=Depends(current_user)):
    store = get_store()
    if not store.get_session(user, sid):
        raise HTTPException(404, 'session not found')
    return store.session_shots(user, sid)


# ----------------------------------------------------------------- Photos upload (standalone, DEC-055)
@app.post('/uploads')
async def upload_clip(file: UploadFile = File(...), metadata: str = Form('{}'),
                      user=Depends(current_user)):
    """Analyze a clip from Photos as a STANDALONE upload (DEC-055). It is never attached to a session
    (session_id stays null), so it never shows in Recent sessions / activity and never feeds Stats, the
    LaneSight Score, tiers or achievements. Same serial analyze path; the shot result is viewable and is
    listed under Lab › Uploads (GET /me/uploads)."""
    store = get_store()
    meta = json.loads(metadata or '{}')
    cfg, ub = _ball_link(store, user, meta)
    # De-duplicate by content hash (handoff E): an identical re-upload returns the existing shot instead of
    # running a second analysis. Read the bytes once; reuse them for the write below.
    import hashlib
    data = await file.read()
    content_hash = hashlib.sha256(data).hexdigest()
    dup = (store.find_upload_by_hash(user, content_hash)
           if (_upload_dedupe_on() and hasattr(store, 'find_upload_by_hash')) else None)
    if dup:
        return {'shot_id': dup['id'], 'duplicate': True, 'source': 'upload'}
    shot = store.create_shot(user, None, {'intent': meta.get('intent'), 'capture_mode': meta.get('capture_mode'),
                                          'source': 'upload', 'sensor_used': meta.get('sensor_used'),
                                          'sensor_id': meta.get('sensor_id'), 'handed': meta.get('handed'),
                                          'ball_configuration_id': cfg, 'user_ball_id': ub, 'oil_pattern_id': meta.get('oil_pattern_id')})
    if hasattr(store, 'set_content_hash'):
        store.set_content_hash(shot['id'], content_hash)
    dest = DATA_ROOT / 'uploads'
    dest.mkdir(parents=True, exist_ok=True)
    path = dest / f"{shot['id']}.mov"
    with open(path, 'wb') as f:
        f.write(data)
    job = _analyze_job(shot['id'], str(path), meta.get('handed'), user, None,
                       mode=(meta.get('capture_mode') or 'shot'), is_upload=True, content_hash=content_hash)
    return {'shot_id': shot['id'], 'job_id': job.id, 'source': 'upload'}


# ---------------------------------------------------------- Storage-based upload (no 32 MiB API cap; cloud)
@app.post('/uploads/signed-url')
def create_upload_url(user=Depends(current_user)):
    """Direct-to-Storage signed upload URL for a clip. The app PUTs the clip bytes to `upload_url` (bypassing
    the API request-size cap), then calls POST /shots/analyze with the returned `path`."""
    store = get_store()
    path = f'{user}/{uuid.uuid4().hex}.mov'            # user-scoped object key
    return store.storage_signed_upload_url('shot-clips', path)


def clip_retention_days() -> int:
    """DEC-100: days a clip stays in the private `shot-clips` bucket after analysis (diagnostics). LaneSight sets
    this, not the user (DEC-099). LANESIGHT_CLIP_RETENTION_DAYS overrides; 0 = delete right after analysis.
    The legacy LANESIGHT_KEEP_CLIPS=1 still means "retain"."""
    raw = os.environ.get('LANESIGHT_CLIP_RETENTION_DAYS')
    if raw is not None:
        try:
            return max(0, int(raw))
        except ValueError:
            pass
    return 7


def clip_keep_max() -> int:
    """Per-user cap on retained clips (newest kept) so the Storage quota can't fill during heavy testing."""
    try:
        return max(1, int(os.environ.get('LANESIGHT_CLIP_KEEP_MAX', '40')))
    except ValueError:
        return 40


@app.post('/analysis/client-failure')
def client_failure(body: dict = Body(...), user=Depends(current_user)):
    """DEC-100: the phone reports an analysis that failed BEFORE it reached the server (trim, signed URL,
    upload, or the analyze request itself dropping). Logged to analysis_attempt so no attempt is invisible."""
    b = dict(body or {})
    stage = str(b.get('stage') or 'unknown')[:40]
    row = {'user_id': user, 'session_id': b.get('session_id'), 'shot_id': None,
           'source': b.get('source') if b.get('source') in ('live', 'upload') else None,
           'capture_mode': b.get('capture_mode') if b.get('capture_mode') in ('shot', 'form') else None,
           'status': 'failed', 'failure_code': f'CLIENT_{stage.upper()}', 'failure_stage': 'client',
           'diagnostics': {'error': str(b.get('error') or '')[:500], 'stage': stage,
                           'app_version': b.get('app_version'), 'clip_bytes': b.get('clip_bytes'),
                           'clip_duration_s': b.get('clip_duration_s')},
           'step_timings': {'client': b.get('client_timings')} if b.get('client_timings') else None,
           'algorithm_version': ALGO_VERSION, 'api_revision': os.environ.get('K_REVISION'),
           'env': 'live' if os.environ.get('K_REVISION') else 'dev'}
    try:
        get_store().log_analysis_attempt(row)
    except Exception as e:
        print(f'client-failure log skipped ({e})')
    return {'logged': True}


@app.post('/analysis/shadow')
def shadow_attempt(body: dict = Body(...), user=Depends(current_user)):
    """DEC-106 Phase-6 prep: the phone's native on-device engine analyses each shot in the BACKGROUND (shadow)
    and submits its result here. Recorded as an analysis_attempt with platform='ios' (DEC-103) — it is NEVER
    shown to the user and NEVER feeds Score/coaching; the server stays authoritative. This lets us compare
    on-device vs server (and, once the DEC-094 ground-truth set exists, vs truth) in the ops layer BEFORE any
    per-metric flip. No flip happens here — ingestion only."""
    b = dict(body or {})
    m = b.get('metrics') or {}
    events = b.get('events') or {}                    # form: per-event TIMES (ball_start_s, release_s, …)
    perf = b.get('device_perf') or {}
    basis = str(b.get('basis') or '')[:20]
    mode = b.get('capture_mode') if b.get('capture_mode') in ('shot', 'form') else 'shot'
    # Measured = the engine produced something (a metric value or, for form, an event time) and didn't
    # self-report unavailable. Works for both ball shots and form.
    measured = basis != 'unavailable' and (
        any(v is not None for v in m.values()) or any(v is not None for v in events.values()))
    # Ball metric keys go to top-level diagnostics so ops.attempt surfaces them (split by platform); the full
    # metric + event dicts are kept for DEC-094 Gate A (per-metric for shot, per-event-time for form).
    diag = {k: m.get(k) for k in ('ball_speed', 'entry_board', 'entry_angle', 'rev_rate', 'n_measured')
            if m.get(k) is not None}
    diag['basis'] = basis or None
    diag['note'] = (str(b.get('note'))[:300] if b.get('note') else None)
    if m:
        diag['metrics'] = m
    if events:
        diag['events'] = events
    dev = {k: perf.get(k) for k in ('latency_s', 'peak_mem_mb', 'thermal_state', 'thermal_transitions',
                                    'battery_delta', 'decode_fps', 'pose_confidence') if perf.get(k) is not None}
    if dev:
        diag['device'] = dev
    lat = perf.get('latency_s')
    row = {'user_id': user,
           'shot_id': b.get('shot_id'),                 # correlate with the server shot (same clip)
           'session_id': b.get('session_id'),
           'source': b.get('source') if b.get('source') in ('live', 'upload') else None,
           'capture_mode': mode,
           'status': 'analyzed' if measured else 'failed',
           'failure_code': None if measured else 'SHADOW_UNAVAILABLE',
           'failure_stage': None if measured else ('form_pose' if mode == 'form' else 'track'),
           'platform': 'ios',                           # DEC-103: the on-device shadow engine
           'algorithm_version': str(b.get('algorithm_version') or 'ios-ondevice')[:60],
           'api_revision': (str(b.get('app_version'))[:60] if b.get('app_version') else None),
           'duration_ms': int(lat * 1000) if isinstance(lat, (int, float)) else None,
           'diagnostics': {k: v for k, v in diag.items() if v is not None},
           'step_timings': {'client': b.get('timings')} if b.get('timings') else None,
           'env': 'live' if os.environ.get('K_REVISION') else 'dev'}
    try:
        get_store().log_analysis_attempt(row)
    except Exception as e:
        print(f'shadow attempt log skipped ({e})')
    return {'logged': True, 'platform': 'ios', 'status': row['status']}


@app.post('/shots/analyze')
async def analyze_from_storage(body: dict = Body(...), user=Depends(current_user)):
    """Analyze a clip already uploaded to Storage. body: {storage_path, session_id?, metadata?}. With a
    session_id it's a live session shot (feeds Score/Stats); without, a standalone upload (DEC-055). The clip
    is downloaded (service role), analyzed on the same serial path, then RETAINED for the diagnostic window
    (DEC-100, default 7 days) — or deleted right away when retention is 0."""
    store = get_store()
    storage_path = body.get('storage_path')
    if not storage_path or not storage_path.startswith(f'{user}/'):
        raise HTTPException(403, 'storage_path missing or not owned by the user')
    session_id = body.get('session_id')
    meta = body.get('metadata') or {}
    is_upload = session_id is None
    if session_id is not None and not get_store().get_session(user, session_id):
        raise HTTPException(404, 'session not found')
    cfg, ub = _ball_link(store, user, meta)
    data = store.storage_download('shot-clips', storage_path)
    import hashlib
    content_hash = hashlib.sha256(data).hexdigest()
    if is_upload:
        dup = (store.find_upload_by_hash(user, content_hash)
               if (_upload_dedupe_on() and hasattr(store, 'find_upload_by_hash')) else None)
        if dup:
            store.storage_delete('shot-clips', storage_path)
            return {'shot_id': dup['id'], 'duplicate': True, 'source': 'upload'}
    else:
        # Live-shot retry idempotency: a dropped-connection re-send carries identical clip bytes, so return the
        # already-analyzed shot in this session instead of creating a duplicate (C4; serial queue avoids races).
        dup = store.find_shot_by_hash(user, content_hash, session_id) if hasattr(store, 'find_shot_by_hash') else None
        if dup:
            store.storage_delete('shot-clips', storage_path)
            return {'shot_id': dup['id'], 'duplicate': True, 'source': 'live'}
    shot = store.create_shot(user, session_id,
                             {'intent': meta.get('intent'), 'capture_mode': meta.get('capture_mode'),
                              'source': 'upload' if is_upload else meta.get('source', 'live'),
                              'sensor_used': meta.get('sensor_used'), 'sensor_id': meta.get('sensor_id'),
                              'handed': meta.get('handed'), 'ball_configuration_id': cfg, 'user_ball_id': ub, 'oil_pattern_id': meta.get('oil_pattern_id')})
    if hasattr(store, 'set_content_hash'):                  # live shots too, so a retry can dedupe (above)
        store.set_content_hash(shot['id'], content_hash)
    dest = DATA_ROOT / ('uploads' if is_upload else 'sessions')
    dest.mkdir(parents=True, exist_ok=True)
    local = dest / f"{shot['id']}.mov"
    with open(local, 'wb') as f:
        f.write(data)
    days = clip_retention_days()
    job = _analyze_job(shot['id'], str(local), meta.get('handed'), user, session_id,
                       mode=(meta.get('capture_mode') or 'shot'), is_upload=is_upload, content_hash=content_hash,
                       client_timings=body.get('client_timings'),
                       clip_storage_path=storage_path if days > 0 else None)
    if days > 0:
        # DEC-100: keep the clip for a short diagnostic window (default 7 days, newest CLIP_KEEP_MAX per user)
        # so every analysis can be reproduced and debugged. Owner-only access via the service role; the
        # bucket is private. Old clips are purged here, best effort, on every analysis.
        try:
            store.purge_old_clips('shot-clips', user, days=days, keep_max=clip_keep_max())
        except Exception as pe:
            print(f'clip purge skipped ({type(pe).__name__}: {pe})')
    else:
        store.storage_delete('shot-clips', storage_path)  # retention off: clip analyzed; don't retain it
    try:
        os.remove(local)
    except OSError:
        pass
    return {'shot_id': shot['id'], 'job_id': job.id, 'source': 'upload' if is_upload else 'live'}


@app.get('/me/uploads')
def me_uploads(user=Depends(current_user)):
    """Standalone upload analyses for the Lab › Uploads list (DEC-055). Newest first; each row opens its
    shot result. Never includes live/session shots."""
    return get_store().list_uploads(user)


# ----------------------------------------------------------------- stats
@app.get('/me/stats')
def me_stats(view: str = 'throw', range: str | None = None, user=Depends(current_user)):
    return engines.user_stats(get_store(), user, view=view, range_=range)


@app.get('/me/stats/equipment')
def me_stats_equipment(user=Depends(current_user)):
    """Stats · Equipment (v3.7): per-ball and per-oil-pattern rollups — shots, mean speed/rev, and pocket %
    (the scorer's handedness-mirrored entry-board range). Reuses the tested performance()/summary() over each
    group's shots. A ball/pattern with no measured shots simply doesn't appear; nulls stay null."""
    from lanesight_core.score import performance
    from lanesight_core.insights import session as si
    store = get_store()
    points = store.shot_points(user)
    params = store.score_formula_params()
    prof = store.get_profile(user) or {}
    handed = (prof.get('handed') or 'R').upper()
    pat_names = {p['id']: p.get('name') for p in (store.oil_patterns() or []) if p.get('id')}
    ball_names: dict = {}
    for b in (store.list_arsenal(user) or []):
        label = b.get('name') or b.get('nickname') or b.get('model_name')
        for k in (b.get('ball_configuration_id'), b.get('id')):
            if k: ball_names[k] = label

    def agg(key, names):
        groups: dict = {}
        for p in points:
            k = p.get(key)
            if not k:
                continue
            groups.setdefault(k, []).append(p['record'])
        out = []
        for k, recs in groups.items():
            perf = performance(recs, params, handed)
            sm = si.summary(recs)
            out.append({'id': k, 'name': names.get(k), 'n': len(recs),
                        'speed': (sm.get('ball_speed') or {}).get('mean'),
                        'rev': (sm.get('rev_rate') or {}).get('mean'),
                        'entry_angle': (sm.get('entry_angle') or {}).get('mean'),
                        'pocket_pct': perf.get('pocket_pct')})
        return sorted(out, key=lambda r: -r['n'])

    return {'by_ball': agg('ball', ball_names), 'by_pattern': agg('pattern', pat_names)}


@app.get('/me/stats/metric/{metric}')
def me_metric_detail(metric: str, user=Depends(current_user)):
    """Per-metric detail for a Stats detail screen (MVP-08): avg, robust spread, range, coverage, per-session
    trend, by ball, by oil pattern, small-sample flag (<20)."""
    from lanesight_core.insights import session as si
    return si.metric_detail(get_store().shot_points(user), metric)


# ----------------------------------------------------------------- achievements
def _grouped_achievements(store, user):
    engines.run_achievements(store, user, 'read')             # idempotent: keep progress fresh
    defs = store.achievement_defs()
    prog = {(p['achievement_id'], p.get('level', 1)): p for p in store.list_ach_progress(user)}
    unlocked = {u['achievement_id'] for u in store.list_ach_unlocks(user)}
    cats: dict[str, list] = {}
    active_unlocked = 0
    for d in defs:
        p = prog.get((d['id'], 1), {})
        is_unlocked = d['id'] in unlocked
        if is_unlocked and d['status'] == 'active':
            active_unlocked += 1
        cats.setdefault(d['category'], []).append({
            'id': d['id'], 'name': d['name'], 'description': d['description'], 'category': d['category'],
            'status': d['status'], 'inactive_reason': d.get('inactive_reason'),
            'progress_status': 'unlocked' if is_unlocked else p.get('status', 'locked'),
            'current_value': p.get('current_value'), 'target_value': p.get('target_value'),
            'best_value': p.get('best_value'), 'qualifying_count': p.get('qualifying_count'),
            'sample_count': p.get('sample_count'), 'unavailable_reason': p.get('unavailable_reason'),
            'unlocked': is_unlocked})
    return {'unlocked_count': active_unlocked, 'categories': cats, 'pins': store.get_pins(user)}

@app.get('/me/achievements')
def me_achievements(user=Depends(current_user)):
    return _grouped_achievements(get_store(), user)

@app.get('/me/achievements/{ach_id}')
def me_achievement_detail(ach_id: str, user=Depends(current_user)):
    store = get_store()
    engines.run_achievements(store, user, 'read')
    d = next((x for x in store.achievement_defs() if x['id'] == ach_id), None)
    if not d:
        raise HTTPException(404, 'achievement not found')
    p = next((x for x in store.list_ach_progress(user)
              if x['achievement_id'] == ach_id and x.get('level', 1) == 1), {})
    unlock = store.get_ach_unlock(user, ach_id, 1)
    evidence = (p.get('evidence_ref') or {}).get('shot_ids', []) if p else []
    return {'id': d['id'], 'name': d['name'], 'description': d['description'], 'category': d['category'],
            'status': d['status'], 'inactive_reason': d.get('inactive_reason'),
            'progress': {k: p.get(k) for k in ('status', 'current_value', 'target_value', 'best_value',
                                               'qualifying_count', 'sample_count', 'unavailable_reason')},
            'evidence_shot_ids': evidence,
            'unlocked': bool(unlock), 'unlocked_at': (unlock or {}).get('unlocked_at'),
            'rule_version': d.get('rule_version', 1)}

@app.put('/me/achievements/pins')
def me_achievement_pins(body: dict, user=Depends(current_user)):
    return {'pins': get_store().set_pins(user, (body or {}).get('pins', []))}


# ----------------------------------------------------------------- notifications
@app.get('/me/notifications')
def me_notifications(undelivered: int = 0, user=Depends(current_user)):
    return get_store().list_notifications(user, undelivered=bool(undelivered))

@app.post('/me/notifications/{notif_id}/delivered')
def notification_delivered(notif_id: str, user=Depends(current_user)):
    r = get_store().mark_notification(user, notif_id, 'delivered_at')
    if not r:
        raise HTTPException(404, 'notification not found')
    return r

@app.post('/me/notifications/{notif_id}/dismiss')
def notification_dismiss(notif_id: str, user=Depends(current_user)):
    r = get_store().mark_notification(user, notif_id, 'dismissed_at')
    if not r:
        raise HTTPException(404, 'notification not found')
    return r


# ----------------------------------------------------------------- recent activity
@app.get('/me/activity')
def me_activity(user=Depends(current_user)):
    return get_store().list_activity(user)


# ----------------------------------------------------------------- account deletion
@app.delete('/me')
def delete_me(user=Depends(current_user)):
    store = get_store()
    session_ids = [s['id'] for s in store.list_sessions(user)]
    shot_ids = [sh['id'] for sh in store.user_shots(user)]
    avatar_path = (store.get_avatar(user) or {}).get('avatar_path') if hasattr(store, 'get_avatar') else None
    store.delete_user(user)                                   # auth user + cascaded rows (live)
    if avatar_path:                                           # remove the user's photo on this Mac
        try:
            (DATA_ROOT / avatar_path).unlink()
        except OSError:
            pass
    for sid in session_ids:                                   # remove the user's videos on this Mac
        shutil.rmtree(DATA_ROOT / 'sessions' / sid, ignore_errors=True)
    for shid in shot_ids:
        for f in (DATA_ROOT / 'out').glob(f'{shid}*'):
            try:
                f.unlink()
            except OSError:
                pass
        # standalone upload clips live under uploads/<shot_id>.mov (DEC-055), not under a session dir
        try:
            (DATA_ROOT / 'uploads' / f'{shid}.mov').unlink()
        except OSError:
            pass
    return {'deleted': True}
