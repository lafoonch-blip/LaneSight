#!/usr/bin/env bash
# DEC-129: fetch the MediaPipe Pose Landmarker iOS framework + the pose model for the on-device Form engine.
# Both are LARGE binaries and gitignored (never committed). Run once per machine before building:
#   ios/LaneSight/Vendor/fetch_mediapipe.sh
# Then uncomment the `dependencies` block in project.yml and `xcodegen generate`.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"          # ios/LaneSight/Vendor
IOS="$(dirname "$HERE")"                         # ios/LaneSight
MODELS="$IOS/Models"

MP_VERSION="1.0.0"
# MediaPipeTasksVision is just the Obj-C wrapper; MediaPipeTasksCommon carries the heavy TFLite/XNNPACK binary.
# Both are vendored static xcframeworks (MediaPipeTasksCommon depends on nothing further).
declare -a MP_URLS=(
  "https://dl.google.com/cpdc/20260727-225049/MediaPipeTasksVision-${MP_VERSION}.tar.gz"
  "https://dl.google.com/cpdc/20260727-225047/MediaPipeTasksCommon-${MP_VERSION}.tar.gz"
)
declare -a MP_FWS=(MediaPipeTasksVision MediaPipeTasksCommon)

mkdir -p "$HERE" "$MODELS"

for i in "${!MP_FWS[@]}"; do
  fw="${MP_FWS[$i]}"; url="${MP_URLS[$i]}"
  dst="$HERE/$fw.xcframework"
  if [ -d "$dst" ]; then
    echo "[fetch] $fw.xcframework already present — skipping"
    continue
  fi
  echo "[fetch] downloading $fw ${MP_VERSION} ..."
  tmp="$(mktemp -d)"
  curl -fL --retry 3 --max-time 900 "$url" -o "$tmp/mp.tar.gz"
  echo "[fetch] extracting $fw ..."
  tar -xzf "$tmp/mp.tar.gz" -C "$tmp"
  src="$(find "$tmp" -maxdepth 4 -type d -name "$fw.xcframework" | head -1)"
  [ -n "$src" ] || { echo "[fetch] ERROR: $fw.xcframework not found in tarball"; exit 1; }
  rm -rf "$dst"; cp -R "$src" "$dst"
  echo "[fetch] -> $dst ($(du -sh "$dst" | cut -f1))"
  # MediaPipeTasksCommon also ships the heavy force-loaded graph libs (abseil/tflite/xnnpack/protobuf).
  gl="$(find "$tmp" -maxdepth 4 -type d -name graph_libraries | head -1)"
  if [ -n "$gl" ]; then
    mkdir -p "$HERE/graph_libraries"
    cp "$gl"/*.a "$HERE/graph_libraries/"
    echo "[fetch] -> $HERE/graph_libraries ($(du -sh "$HERE/graph_libraries" | cut -f1))"
  fi
  rm -rf "$tmp"
done

# pose model: copy from ~/LaneSightData/models (the server reference's model; sha256 pinned in form/pose.py).
MODEL_SRC="${LANESIGHT_POSE_MODEL:-$HOME/LaneSightData/models/pose_landmarker_heavy.task}"
MODEL_DST="$MODELS/pose_landmarker_heavy.task"
if [ -f "$MODEL_DST" ]; then
  echo "[fetch] pose model already present — skipping"
elif [ -f "$MODEL_SRC" ]; then
  cp "$MODEL_SRC" "$MODEL_DST"
  echo "[fetch] pose model -> $MODEL_DST"
else
  echo "[fetch] WARNING: pose model not found at $MODEL_SRC — Form on-device will fall back to the server"
fi

echo "[fetch] done. Next: uncomment the MediaPipe dependency in project.yml, then run: xcodegen generate"
