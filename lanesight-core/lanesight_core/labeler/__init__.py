"""LaneSight Labeler — a reusable, local, frame-accurate video event labeler.

Each labeling job is a small task file in `validation/label_tasks/*.json` (which clips, which moments to mark,
optional hints). Labels save to `validation/labels/<task>.json` on every change, and can also be exported to
whatever file a pipeline step already reads (see `export` in a task file).

Start it by double-clicking `LaneSight Labeler.command` at the repo root, or:
    python -m lanesight_core.labeler
"""
