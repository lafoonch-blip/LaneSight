"""Lightweight local landmark verification tool (Step 2). Pure Python on cv2 HighGUI — no extra deps, not a
production feature. Opens each stabilized plate, overlays UNVERIFIED auto-suggestions, and lets you
accept / drag / reject / add / mark-not-visible / mark-ambiguous, with zoom + pan for precise placement.

Safeguards (Step 3), enforced here and in the schema:
- Coordinates are stored in ORIGINAL plate pixels (view<->image transform below), never scaled-preview coords.
- Only VERIFIED points calibrate (schema `usable`); ambiguous / not-visible / suggested are excluded.
- Loading suggestions NEVER overwrites an existing VERIFIED label (merge keeps verified).
- Suggested (amber) vs verified (green) stay visually distinct.

Run:
  python -m lanesight_core.cv.calib.label_tool DIR            # DIR has *.plate.png (+ optional *.landmarks.json)
  python -m lanesight_core.cv.calib.label_tool DIR --autofill # also seed suggestions from the stab pickles

Keys (shown in the window title bar / console):
  [ ]   cycle the 'armed' landmark (the one a left-click will place)
  click place armed landmark (or select the nearest existing point)
  drag  move the selected point
  a     accept selected/armed suggestion -> verified      r  reject -> rejected
  v     mark not-visible        b  mark ambiguous          d/Del  clear the point
  + -   zoom      w a s d / arrows  pan      f  fit to window
  s     save this clip's JSON   n / p  next / prev clip    q / Esc  quit (prompts to save)
"""
from __future__ import annotations
import os
import glob
import numpy as np

from .landmarks import (LandmarkSet, LandmarkObservation, STATUS_VERIFIED, STATUS_SUGGESTED,
                        STATUS_REJECTED, STATUS_AMBIGUOUS, STATUS_NOT_VISIBLE)
from .lane_geometry import CANONICAL

# landmark cycle order: exact anchors first (foul + pins — what actually calibrates), then the USBC-interval
# landmarks (consistency checks). GUIDANCE (Shayne): do NOT force a barely-visible landmark — select it and
# press 'b' (ambiguous) or 'v' (not-visible). We want to find out whether the video HAS the information, not
# to manufacture a calibration. Interval landmarks (arrows/dots/targets) never become exact anchors.
ARM_ORDER = (["foul_l", "foul_r"]
             + [f"pin_{i}" for i in range(1, 11)]
             + [f"approach_dot_{b}" for b in (5, 10, 15, 20, 25, 30, 35)]
             + [f"arrow_{b}" for b in (5, 10, 15, 20, 25, 30, 35)]
             + [f"downlane_target_{b}" for b in (5, 10, 15, 20, 25, 30, 35)]
             + [f"dot_{b}" for b in (5, 10, 15, 20, 25, 30, 35)])


# ------------------------------------------------------------------ pure helpers (testable headless)

def view_to_image(vx, vy, view):
    """Window/view pixel -> ORIGINAL image pixel."""
    return (view["ox"] + vx / view["zoom"], view["oy"] + vy / view["zoom"])


def image_to_view(ix, iy, view):
    """ORIGINAL image pixel -> window/view pixel."""
    return ((ix - view["ox"]) * view["zoom"], (iy - view["oy"]) * view["zoom"])


def merge_existing_and_suggestions(existing: LandmarkSet, suggestions: LandmarkSet) -> LandmarkSet:
    """Keep every VERIFIED point from `existing`; fill the rest from `suggestions`. Never clobbers verified
    work (Step 3). Returns a new LandmarkSet keyed over the union of names."""
    out_obs = {}
    names = list(dict.fromkeys(list(existing.observations) + list(suggestions.observations)))
    for n in names:
        e = existing.observations.get(n)
        if e is not None and e.usable:                      # verified -> untouchable
            out_obs[n] = e
        elif n in suggestions.observations and suggestions.observations[n].labeled:
            out_obs[n] = suggestions.observations[n]
        elif e is not None:
            out_obs[n] = e
        else:
            out_obs[n] = suggestions.observations[n]
    size = existing.image_size if existing.image_size != (0, 0) else suggestions.image_size
    return LandmarkSet(clip_id=existing.clip_id or suggestions.clip_id, image_size=size, observations=out_obs,
                       notes=existing.notes or suggestions.notes)


def _load_or_init(plate_path, use_autofill):
    """Return a LandmarkSet for a plate: existing JSON merged with (optional) fresh autofill suggestions."""
    import cv2
    clip = os.path.basename(plate_path)[:-len(".plate.png")]
    json_path = plate_path.replace(".plate.png", ".landmarks.json")
    img = cv2.imread(plate_path)
    h, w = img.shape[:2]
    existing = LandmarkSet.from_json(json_path) if os.path.exists(json_path) else LandmarkSet.template(clip, (w, h))
    if use_autofill:
        stab = _find_stab(clip)
        if stab:
            from .autofill import autofill
            existing = merge_existing_and_suggestions(existing, autofill(stab, log=lambda *a, **k: None))
    return img, existing, json_path


def _find_stab(clip):
    base = "/Users/shaynel/Developer/LaneSight/10-25 training videos"
    for p in (os.path.join(base, f"{clip}_stab.pkl"), os.path.join(base, "_results", clip, f"{clip}_stab.pkl")):
        if os.path.exists(p):
            return p
    return None


# ------------------------------------------------------------------ interactive editor (cv2 HighGUI)

class LabelEditor:
    def __init__(self, plate_dir, use_autofill=False, win=(760, 1040)):
        self.plates = sorted(glob.glob(os.path.join(plate_dir, "*.plate.png")))
        if not self.plates:
            raise SystemExit(f"no *.plate.png in {plate_dir}")
        self.use_autofill = use_autofill
        self.win_w, self.win_h = win
        self.idx = 0
        self.armed = 0
        self.sel = None                 # name of the currently selected point
        self.dragging = False
        self.dirty = False
        self._load(self.idx)

    def _load(self, i):
        self.img, self.ls, self.json_path = _load_or_init(self.plates[i], self.use_autofill)
        self.dirty = False
        self.sel = None
        self.view = self._fit_view()

    def _fit_view(self):
        h, w = self.img.shape[:2]
        z = min(self.win_w / w, self.win_h / h)
        return dict(zoom=z, ox=0.0, oy=0.0)

    # ---- rendering
    def render(self):
        import cv2
        h, w = self.img.shape[:2]
        z = self.view["zoom"]
        sw, sh = int(self.win_w / z), int(self.win_h / z)
        ox = int(np.clip(self.view["ox"], 0, max(0, w - sw)))
        oy = int(np.clip(self.view["oy"], 0, max(0, h - sh)))
        self.view["ox"], self.view["oy"] = float(ox), float(oy)
        crop = self.img[oy:min(oy + sh, h), ox:min(ox + sw, w)]
        canvas = cv2.resize(crop, (int(crop.shape[1] * z), int(crop.shape[0] * z)), interpolation=cv2.INTER_NEAREST)
        out = np.zeros((self.win_h, self.win_w, 3), np.uint8)
        out[:canvas.shape[0], :canvas.shape[1]] = canvas
        colors = {STATUS_VERIFIED: (0, 255, 0), STATUS_SUGGESTED: (0, 200, 255),
                  STATUS_AMBIGUOUS: (160, 160, 160), STATUS_NOT_VISIBLE: (110, 110, 110)}
        for n, ob in self.ls.observations.items():
            if not ob.labeled or ob.status == STATUS_REJECTED:
                continue
            vx, vy = image_to_view(ob.x, ob.y, self.view)
            if not (0 <= vx < self.win_w and 0 <= vy < self.win_h):
                continue
            c = colors.get(ob.status, (0, 255, 0))
            r = 7 if n == self.sel else 4
            cv2.circle(out, (int(vx), int(vy)), r, c, 2 if n == self.sel else -1)
            cv2.putText(out, n, (int(vx) + 6, int(vy) - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.4, c, 1, cv2.LINE_AA)
        hud = (f"{self.ls.clip_id} [{self.idx+1}/{len(self.plates)}]  arm:{ARM_ORDER[self.armed]}  "
               f"sel:{self.sel or '-'}  verified:{self.ls.verified_count()} sugg:{self.ls.suggested_count()}  "
               f"{'*UNSAVED' if self.dirty else ''}")
        cv2.rectangle(out, (0, 0), (self.win_w, 22), (20, 20, 20), -1)
        cv2.putText(out, hud, (6, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1, cv2.LINE_AA)
        return out

    def _nearest(self, ix, iy, tol_img=14):
        best, bd = None, tol_img
        for n, ob in self.ls.observations.items():
            if not ob.labeled or ob.status == STATUS_REJECTED:
                continue
            d = np.hypot(ob.x - ix, ob.y - iy)
            if d < bd:
                best, bd = n, d
        return best

    # ---- mouse: left = place/select/drag a landmark; right-drag = pan; wheel = zoom
    def on_mouse(self, event, x, y, flags, _):
        import cv2
        ix, iy = view_to_image(x, y, self.view)
        if event == cv2.EVENT_LBUTTONDOWN:
            hit = self._nearest(ix, iy)
            if hit:
                self.sel = hit
                self.dragging = True
            else:
                name = ARM_ORDER[self.armed]
                self.ls.set_point(name, ix, iy)            # verified + manual
                self.sel = name
                self.dirty = True
        elif event == cv2.EVENT_MOUSEMOVE and self.dragging and self.sel:
            self.ls.set_point(self.sel, ix, iy, source="manual-adjusted")
            self.dirty = True
        elif event == cv2.EVENT_LBUTTONUP:
            self.dragging = False
        elif event == cv2.EVENT_RBUTTONDOWN:
            self._pan_anchor = (x, y, self.view["ox"], self.view["oy"])
        elif event == cv2.EVENT_MOUSEMOVE and (flags & cv2.EVENT_FLAG_RBUTTON) and getattr(self, "_pan_anchor", None):
            x0, y0, ox0, oy0 = self._pan_anchor
            self.view["ox"] = ox0 - (x - x0) / self.view["zoom"]
            self.view["oy"] = oy0 - (y - y0) / self.view["zoom"]
        elif event == cv2.EVENT_MOUSEWHEEL:
            self.view["zoom"] *= (1.25 if flags > 0 else 0.8)

    # ---- keys (no clashes with save/nav; pan is right-drag)
    def on_key(self, k):
        if k in (ord('['), ord(']')):
            self.armed = (self.armed + (1 if k == ord(']') else -1)) % len(ARM_ORDER)
        elif k == ord('a') and self.sel:                   # accept suggestion -> verified
            ob = self.ls.observations[self.sel]
            if ob.labeled:
                self.ls.observations[self.sel] = LandmarkObservation(
                    self.sel, ob.x, ob.y, status=STATUS_VERIFIED, source=ob.source or "accepted")
                self.dirty = True
        elif k == ord('r') and self.sel:
            self._mark(STATUS_REJECTED)
        elif k == ord('v') and self.sel:
            self._mark(STATUS_NOT_VISIBLE)
        elif k == ord('b') and self.sel:
            self._mark(STATUS_AMBIGUOUS)
        elif k in (ord('d'), 8, 127) and self.sel:
            self.ls.observations[self.sel] = LandmarkObservation(self.sel, None, None)
            self.sel = None; self.dirty = True
        elif k in (ord('+'), ord('=')):
            self.view["zoom"] *= 1.25
        elif k == ord('-'):
            self.view["zoom"] = max(0.1, self.view["zoom"] / 1.25)
        elif k == ord('f'):
            self.view = self._fit_view()

    def _mark(self, status):
        ob = self.ls.observations[self.sel]
        self.ls.observations[self.sel] = LandmarkObservation(self.sel, ob.x, ob.y, status=status, source=ob.source)
        self.dirty = True

    def save(self):
        self.ls.to_json(self.json_path)
        self.dirty = False
        print(f"saved {self.json_path} ({self.ls.verified_count()} verified)")

    def run(self):
        import cv2
        name = "LaneSight landmark labeler"
        cv2.namedWindow(name, cv2.WINDOW_AUTOSIZE)
        cv2.setMouseCallback(name, self.on_mouse)
        print(__doc__)
        while True:
            cv2.imshow(name, self.render())
            k = cv2.waitKey(20) & 0xFF
            if k == 255:
                continue
            if k in (ord('q'), 27):
                if self.dirty:
                    self.save()
                break
            elif k == ord('s'):
                self.save()
            elif k in (ord('n'), ord('p')):
                if self.dirty:
                    self.save()
                self.idx = (self.idx + (1 if k == ord('n') else -1)) % len(self.plates)
                self._load(self.idx)
            else:
                self.on_key(k)
        cv2.destroyAllWindows()


def _selftest(plate_dir):
    """Headless: exercise the coordinate transform + merge safeguards + render one overlay PNG (no window)."""
    import cv2
    # coordinate round-trip
    view = dict(zoom=0.4, ox=120.0, oy=340.0)
    for ix, iy in ((0, 0), (1080, 1920), (537.5, 999.25)):
        vx, vy = image_to_view(ix, iy, view)
        rx, ry = view_to_image(vx, vy, view)
        assert abs(rx - ix) < 1e-6 and abs(ry - iy) < 1e-6, (ix, iy, rx, ry)
    # merge never clobbers a verified point
    ex = LandmarkSet.template("C", (1080, 1920)); ex.set_point("foul_l", 300, 1500)
    sg = LandmarkSet.template("C", (1080, 1920)); sg.suggest("foul_l", 999, 999, 0.9, "auto"); sg.suggest("foul_r", 700, 1500, 0.9, "auto")
    m = merge_existing_and_suggestions(ex, sg)
    assert m.observations["foul_l"].x == 300 and m.observations["foul_l"].status == STATUS_VERIFIED
    assert m.observations["foul_r"].status == STATUS_SUGGESTED
    # render an overlay for the first plate (visual sanity, no GUI)
    plates = sorted(glob.glob(os.path.join(plate_dir, "*.plate.png")))
    if plates:
        from .landmarks import render_overlay
        img, ls, _ = _load_or_init(plates[0], use_autofill=False)
        out = os.path.join(plate_dir, "_selftest_overlay.png")
        cv2.imwrite(out, render_overlay(img, ls))
        print(f"selftest OK; wrote {out}")
    else:
        print("selftest OK (no plates to render)")


if __name__ == "__main__":
    import sys
    args = sys.argv[1:]
    if not args:
        print(__doc__); raise SystemExit
    if "--selftest" in args:
        _selftest(args[0]); raise SystemExit
    LabelEditor(args[0], use_autofill=("--autofill" in args)).run()
