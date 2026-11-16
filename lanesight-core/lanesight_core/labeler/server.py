"""Local web server for the LaneSight Labeler. Stdlib only (plus opencv for decoding). Listens on 127.0.0.1.

    python -m lanesight_core.labeler [--port 8790] [--no-open] [--search ~/LaneSightData ...]
"""
from __future__ import annotations

import argparse
import json
import os
import socket
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

from .core import (DEFAULT_SEARCH, LABEL_DIR, REPO_ROOT, TASK_DIR, ClipFinder, FramePool, LabelStore,
                   clip_complete, load_tasks, task_progress)

PAGE = os.path.join(os.path.dirname(__file__), 'page.html')


class App:
    def __init__(self, task_dir=TASK_DIR, label_dir=LABEL_DIR, search=None, repo_root=REPO_ROOT):
        self.task_dir = task_dir
        self.finder = ClipFinder(search or DEFAULT_SEARCH)
        self.frames = FramePool()
        self.store = LabelStore(label_dir, repo_root)

    def tasks(self):
        return load_tasks(self.task_dir)        # re-read each time: editing a task file needs no restart

    def task(self, tid):
        t = self.tasks().get(tid)
        if t is None:
            raise KeyError(f'no task {tid}')
        return t

    def clip_meta(self, clip_id):
        path = self.finder.find(clip_id)
        if not path:
            return {'found': False}
        try:
            src = self.frames.source(path)
        except IOError as e:
            return {'found': True, 'path': path, 'error': str(e)}
        return {'found': True, 'path': path, 'fps': src.fps, 'frames': src.n,
                'name': os.path.basename(path)}

    # ---- API payloads
    def list_tasks(self):
        out = []
        for t in self.tasks().values():
            data = self.store.load(t['id'])
            done, total = task_progress(t, data)
            out.append({'id': t['id'], 'title': t['title'], 'done': done, 'total': total,
                        'error': t.get('error')})
        return {'tasks': out, 'search': self.finder.roots, 'task_dir': self.task_dir}

    def task_payload(self, tid):
        t = self.task(tid)
        data = self.store.load(tid)
        clips = []
        for c in t['clips']:
            lab = data['clips'].get(c['id']) or {}
            clips.append({**c, 'labels': lab, 'complete': clip_complete(t, lab)})
        return {k: v for k, v in t.items() if not k.startswith('_')} | {
            'clips': clips, 'labels_file': os.path.relpath(self.store.path(tid), self.store.repo_root),
            'export_file': (t.get('export') or {}).get('path')}


class Handler(BaseHTTPRequestHandler):
    app: App = None

    def log_message(self, *a):          # quiet console
        pass

    def _send(self, code, body, ctype='application/json', headers=None):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _err(self, code, msg):
        self._send(code, {'error': msg})

    def do_GET(self):
        u = urlparse(self.path)
        parts = [unquote(p) for p in u.path.strip('/').split('/') if p]
        try:
            if not parts:
                with open(PAGE, 'rb') as f:
                    return self._send(200, f.read(), 'text/html; charset=utf-8')
            if parts == ['api', 'tasks']:
                return self._send(200, self.app.list_tasks())
            if len(parts) == 3 and parts[:2] == ['api', 'task']:
                return self._send(200, self.app.task_payload(parts[2]))
            if len(parts) == 3 and parts[:2] == ['api', 'clip']:
                return self._send(200, self.app.clip_meta(parts[2]))
            if len(parts) == 4 and parts[:2] == ['api', 'frame']:
                path = self.app.finder.find(parts[2])
                if not path:
                    return self._err(404, f'clip {parts[2]} not found')
                fr = self.app.frames.source(path).get(int(parts[3]))
                return self._send(200, fr['jpeg'], 'image/jpeg',
                                  {'X-Frame-Index': str(fr['index']), 'X-Frame-Pts': str(fr['pts'])})
            return self._err(404, 'not found')
        except KeyError as e:
            return self._err(404, str(e))
        except (ValueError, IOError) as e:
            return self._err(400, str(e))

    def do_POST(self):
        u = urlparse(self.path)
        parts = [unquote(p) for p in u.path.strip('/').split('/') if p]
        try:
            n = int(self.headers.get('Content-Length') or 0)
            body = json.loads(self.rfile.read(n) or b'{}')
            if len(parts) == 4 and parts[:2] == ['api', 'label']:
                t = self.app.task(parts[2])
                if parts[3] not in {c['id'] for c in t['clips']}:
                    return self._err(404, f'clip {parts[3]} not in task')
                meta = self.app.clip_meta(parts[3])
                self.app.store.update(t, parts[3], body, fps=meta.get('fps'))
                return self._send(200, self.app.task_payload(parts[2]))
            return self._err(404, 'not found')
        except KeyError as e:
            return self._err(404, str(e))
        except (ValueError, TypeError) as e:
            return self._err(400, str(e))


def _free_port(preferred):
    for p in [preferred] + list(range(preferred + 1, preferred + 20)):
        with socket.socket() as s:
            try:
                s.bind(('127.0.0.1', p))
                return p
            except OSError:
                continue
    raise OSError('no free port')


def make_server(port=0, **kw):
    Handler.app = App(**kw)
    return ThreadingHTTPServer(('127.0.0.1', port), Handler)


def main(argv=None):
    ap = argparse.ArgumentParser(description='LaneSight Labeler')
    ap.add_argument('--port', type=int, default=8790)
    ap.add_argument('--no-open', action='store_true')
    ap.add_argument('--search', nargs='*', help='folders to look for clips in (default ~/LaneSightData)')
    a = ap.parse_args(argv)
    port = _free_port(a.port)
    srv = make_server(port, search=a.search)
    url = f'http://127.0.0.1:{port}/'
    print(f'LaneSight Labeler running at {url}')
    print('Clips are looked up under:', ', '.join(Handler.app.finder.roots))
    print('Close this window (or press Ctrl-C) to stop.')
    if not a.no_open:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
