"""Hand-labeled image landmarks: schema, JSON round-trip, unlabeled template, and an overlay renderer.

A `LandmarkSet` is the human input to ablation Runs B/C: for one clip, the pixel location of each named
physical landmark in the canonical geometry. Unlabeled landmarks are omitted (or left x=y=None); the solver
uses only landmarks that are labeled here AND have a known world coordinate in the geometry.

We never ship fabricated pixel coordinates for a real clip (CLAUDE.md: no mock numbers). `template()` writes
an EMPTY skeleton for a clip, to be filled with the overlay tool; tests use synthetic, self-consistent sets.
"""
from __future__ import annotations
from dataclasses import dataclass, asdict
from typing import Optional
import json
import numpy as np

from .lane_geometry import LaneGeometry, CANONICAL


@dataclass
class LandmarkObservation:
    name: str
    x: Optional[float]           # image pixel x (stabilized/background-plate coordinates)
    y: Optional[float]           # image pixel y

    @property
    def labeled(self) -> bool:
        return self.x is not None and self.y is not None


@dataclass
class LandmarkSet:
    clip_id: str
    image_size: tuple            # (width, height) of the frame the points were labeled on
    observations: dict           # name -> LandmarkObservation
    coordinate_space: str = "stabilized_background_plate"
    notes: str = ""

    # ---- construction -------------------------------------------------------
    @classmethod
    def template(cls, clip_id: str, image_size, geometry: LaneGeometry = CANONICAL) -> "LandmarkSet":
        """An unlabeled skeleton listing every geometry landmark (x=y=None) for a human to fill."""
        obs = {name: LandmarkObservation(name, None, None) for name in geometry.landmarks}
        return cls(clip_id=clip_id, image_size=tuple(image_size), observations=obs,
                   notes="UNLABELED TEMPLATE — fill pixel coordinates with the overlay tool; "
                         "leave a landmark null if it is not visible in this clip.")

    def set_point(self, name: str, x: float, y: float):
        self.observations[name] = LandmarkObservation(name, float(x), float(y))
        return self

    # ---- correspondences for the solver ------------------------------------
    def correspondences(self, geometry: LaneGeometry = CANONICAL):
        """Matched (world_xy_inches_ft, image_xy_px) for every landmark that is BOTH labeled here AND has a
        fully-known world coordinate in the geometry. Returns (names, world Nx2, image Nx2)."""
        names, world, image = [], [], []
        for name, ob in self.observations.items():
            if not ob.labeled:
                continue
            w = geometry.world_point(name)
            if w is None:
                continue
            names.append(name)
            world.append([w[0], w[1]])
            image.append([ob.x, ob.y])
        return names, np.asarray(world, float).reshape(-1, 2), np.asarray(image, float).reshape(-1, 2)

    def labeled_count(self) -> int:
        return sum(1 for o in self.observations.values() if o.labeled)

    # ---- JSON round-trip ----------------------------------------------------
    def to_dict(self):
        return dict(clip_id=self.clip_id, image_size=list(self.image_size),
                    coordinate_space=self.coordinate_space, notes=self.notes,
                    observations={n: asdict(o) for n, o in self.observations.items()})

    def to_json(self, path: Optional[str] = None, indent: int = 1) -> str:
        s = json.dumps(self.to_dict(), indent=indent)
        if path:
            with open(path, "w") as fh:
                fh.write(s)
        return s

    @classmethod
    def from_dict(cls, d: dict) -> "LandmarkSet":
        obs = {n: LandmarkObservation(o.get("name", n), o.get("x"), o.get("y"))
               for n, o in d.get("observations", {}).items()}
        return cls(clip_id=d["clip_id"], image_size=tuple(d.get("image_size", (0, 0))),
                   observations=obs, coordinate_space=d.get("coordinate_space", "stabilized_background_plate"),
                   notes=d.get("notes", ""))

    @classmethod
    def from_json(cls, path_or_str: str) -> "LandmarkSet":
        try:
            with open(path_or_str) as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            d = json.loads(path_or_str)
        return cls.from_dict(d)


def render_overlay(image, landmark_set: LandmarkSet, geometry: LaneGeometry = CANONICAL, H_world_to_img=None):
    """Draw labeled landmarks (green) and, when a world->image homography is given, the reprojected geometry
    (cyan) so a human can see fit quality. Returns a BGR image; requires cv2. Pure diagnostic — never on the
    production path."""
    import cv2
    out = image.copy()
    for ob in landmark_set.observations.values():
        if ob.labeled:
            cv2.circle(out, (int(ob.x), int(ob.y)), 5, (0, 255, 0), -1)
            cv2.putText(out, ob.name, (int(ob.x) + 6, int(ob.y) - 6),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 0), 1, cv2.LINE_AA)
    if H_world_to_img is not None:
        for name, lm in geometry.known_landmarks().items():
            w = np.array([lm.x_in, lm.z_ft, 1.0])
            p = H_world_to_img @ w
            if abs(p[2]) < 1e-9:
                continue
            x, y = p[0] / p[2], p[1] / p[2]
            cv2.drawMarker(out, (int(x), int(y)), (255, 200, 0), cv2.MARKER_CROSS, 10, 1)
    return out
