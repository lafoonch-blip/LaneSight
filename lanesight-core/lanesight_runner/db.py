"""SQLite store for the local runner. One file, one connection, one lock: the runner is single-user.
The full ShotRecord JSON from lanesight-core is stored as-is; user inputs live in their own columns so the
original video reading is never overwritten (pin corrections are kept next to the original read)."""
from __future__ import annotations
import json, sqlite3, threading
from datetime import datetime, timezone

SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
  id INTEGER PRIMARY KEY,
  started_at TEXT NOT NULL, ended_at TEXT,
  kind TEXT NOT NULL DEFAULT 'practice',          -- practice | league | tournament
  handed TEXT,                                     -- R | L | NULL (auto from video)
  ball_name TEXT, ball_weight_lb REAL, ball_rg_in REAL,
  pattern_name TEXT, pattern_length_ft REAL,
  intent_json TEXT,                                -- current target line, copied onto each new shot
  notes TEXT
);
CREATE TABLE IF NOT EXISTS shots (
  id INTEGER PRIMARY KEY,
  session_id INTEGER NOT NULL REFERENCES sessions(id),
  n INTEGER NOT NULL,
  original_name TEXT, clip_path TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',           -- queued | processing | done | failed
  error TEXT,
  created_at TEXT NOT NULL, started_at TEXT, finished_at TEXT,
  probe_json TEXT, timings_json TEXT, record_json TEXT,
  ball_name TEXT, ball_weight_lb REAL, ball_rg_in REAL,
  intent_json TEXT,
  hit_mark TEXT,                                   -- yes | no | unsure
  pins_override_json TEXT,                         -- corrected standing pins (list); NULL = use video read
  kind_override TEXT,                              -- first | spare; NULL = automatic
  sensor_json TEXT,                                -- manual Ruby entry
  rec_vote TEXT, rec_note TEXT, rec_followed TEXT  -- up|down, free text, yes|no
);
CREATE INDEX IF NOT EXISTS shots_session ON shots(session_id, n);
"""

def now(): return datetime.now(timezone.utc).isoformat(timespec='seconds')

JSON_COLS = {'probe_json', 'timings_json', 'record_json', 'intent_json', 'pins_override_json', 'sensor_json'}

class DB:
    def __init__(self, path):
        self.conn = sqlite3.connect(path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.lock = threading.Lock()
        with self.lock:
            self.conn.executescript(SCHEMA)
            have = {r['name'] for r in self.conn.execute("PRAGMA table_info(sessions)")}
            for col, decl in [('name', 'TEXT'), ('center', 'TEXT'), ('lane', 'INTEGER')]:   # added for the v2 title row
                if col not in have: self.conn.execute(f"ALTER TABLE sessions ADD COLUMN {col} {decl}")
            self.conn.commit()

    def _row(self, r):
        if r is None: return None
        d = dict(r)
        for k in list(d):
            if k in JSON_COLS:
                d[k[:-5]] = json.loads(d.pop(k)) if d[k] else None
        return d

    def q(self, sql, args=()):
        with self.lock:
            return [self._row(r) for r in self.conn.execute(sql, args).fetchall()]

    def x(self, sql, args=()):
        with self.lock:
            cur = self.conn.execute(sql, args); self.conn.commit(); return cur.lastrowid

    # sessions
    def active_session(self):
        r = self.q("SELECT * FROM sessions WHERE ended_at IS NULL ORDER BY id DESC LIMIT 1")
        return r[0] if r else None

    def session(self, sid):
        r = self.q("SELECT * FROM sessions WHERE id=?", (sid,)); return r[0] if r else None

    def sessions(self):
        return self.q("SELECT s.*, (SELECT COUNT(*) FROM shots WHERE session_id=s.id) AS shot_count FROM sessions s ORDER BY id DESC")

    def start_session(self, **kw):
        self.x("UPDATE sessions SET ended_at=? WHERE ended_at IS NULL", (now(),))
        cols = ['started_at'] + [k for k in kw]
        vals = [now()] + [json.dumps(v) if k.endswith('_json') and v is not None else v for k, v in kw.items()]
        return self.x(f"INSERT INTO sessions ({','.join(cols)}) VALUES ({','.join('?' * len(cols))})", vals)

    def update_session(self, sid, **kw):
        if not kw: return
        sets = ', '.join(f"{k}=?" for k in kw)
        vals = [json.dumps(v) if k.endswith('_json') and v is not None else v for k, v in kw.items()]
        self.x(f"UPDATE sessions SET {sets} WHERE id=?", vals + [sid])

    def end_session(self, sid): self.x("UPDATE sessions SET ended_at=? WHERE id=?", (now(), sid))

    # shots
    def add_shot(self, session, original_name, clip_path):
        n = (self.q("SELECT COALESCE(MAX(n),0)+1 AS n FROM shots WHERE session_id=?", (session['id'],))[0]['n'])
        return self.x("""INSERT INTO shots (session_id, n, original_name, clip_path, created_at, ball_name, ball_weight_lb,
                         ball_rg_in, intent_json) VALUES (?,?,?,?,?,?,?,?,?)""",
                      (session['id'], n, original_name, clip_path, now(), session.get('ball_name'), session.get('ball_weight_lb'),
                       session.get('ball_rg_in'), json.dumps(session['intent']) if session.get('intent') else None))

    def shot(self, shot_id):
        r = self.q("SELECT * FROM shots WHERE id=?", (shot_id,)); return r[0] if r else None

    def shots(self, sid):
        return self.q("SELECT * FROM shots WHERE session_id=? ORDER BY n", (sid,))

    def update_shot(self, shot_id, **kw):
        if not kw: return
        sets = ', '.join(f"{k}=?" for k in kw)
        vals = [json.dumps(v) if k.endswith('_json') and v is not None else v for k, v in kw.items()]
        self.x(f"UPDATE shots SET {sets} WHERE id=?", vals + [shot_id])

    def unfinished_shots(self):
        return self.q("SELECT * FROM shots WHERE status IN ('queued','processing') ORDER BY id")
