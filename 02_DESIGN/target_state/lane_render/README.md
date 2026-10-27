# Lane render (DEC-088 reference)
Three.js reference for the Shot card's 3D lane view. Produces the lane images used in Figma (Target state – v3.7 › Shot card frames).
The app draws the same view live from each shot's `path_fit`; this folder is the visual spec, not app code.

- `lane3d.html` — scene: true-scale lane (41.5 in, 39 boards, 60 ft to the head pin), arrows, dots, pins (USBC dimensions), gutters.
  Ball path = cubic Hermite curve through laydown → arrows → breakpoint → entry (entry slope from entry angle); target line = blue band;
  breakpoint/entry rings; optional `cut` (ft) dims the lane past the last measured distance (far lane not read).
- `render3d.js` — headless render: `npm i three@0.169.0 playwright && node render3d.js shots.json` → `lane_d1.png` (off throw), `lane_d2.png` (good throw, lane held), `lane_d3.png` (far lane not read).
- `shots.json` — the sample shots and camera (`cam` [0, 9.5, -22] ft, look-at [0, 0, 33], fov 14.5°, 344×360 pt @3×).
Boards: board 1 = right edge looking at the pins (right-handed view).
