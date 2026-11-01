#!/bin/zsh
# Double-click to start the LaneSight Labeler. Close this window to stop it.
cd "$(dirname "$0")/lanesight-core" || exit 1
if [ -f .venv/bin/activate ]; then
  source .venv/bin/activate
fi
python3 -c "import cv2" 2>/dev/null || { echo "OpenCV not found. In lanesight-core run: python3 -m venv .venv && source .venv/bin/activate && pip install -e ."; read -k1 "?Press any key to close"; exit 1; }
python3 -m lanesight_core.labeler "$@"
