# Label tasks (LaneSight Labeler)

Each `*.json` here is one labeling job. The labeler lists them in its task picker; edit or add a file and reload
the page (no restart needed).

Start the labeler: double-click **`LaneSight Labeler.command`** at the repo root.

Labels save on every click to `validation/labels/<task>.json` (frame number, seconds, status). If a task has an
`export` block, the labeler also writes that file in the format the pipeline step already reads.

## Fields
- `clips`: clip ids (file names without extension). The labeler finds them anywhere under `~/LaneSightData`,
  sub-folders included. Optional per clip: `hints` (event → estimated frame; the player opens there) and
  `static` (extra values copied into the export, e.g. `"view": "side"`).
- `events`: the moments to mark, in order. `export_key` / `export_unit` (`frame` or `seconds`) control the export.
- `fields`: extra values per clip (`type`: `int`, `float` or `text`; `required: true` keeps the clip open until set).
- `export`: `path` (relative to the repo root), optional `wrap` (top-level key) and `add_fps`.

Frame numbers are 0-based in decode order, the same numbering the pipeline uses. Seconds = frame ÷ fps.
"Not visible" exports as `null`.
