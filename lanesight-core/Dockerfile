# LaneSight backend (API + CV pipeline) for cloud hosting — removes the Mac dependency (DEPLOY_FLY.md).
# Ball (shot) analysis path. Classical OpenCV (headless, no GUI, no GPU); data/auth live in Supabase.
# FORM analysis (mediapipe + the 29 MB pose model) is a deliberate FOLLOW-UP — see the note at the bottom —
# so the first deploy stays small and reliable. Importing the form package is safe without mediapipe (the
# mediapipe import is lazy, inside the pose backend), so the API starts fine; only analyzing a *form* clip
# would need it.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    MPLBACKEND=Agg \
    LANESIGHT_DATA=/data

# opencv-python-headless needs libglib2.0-0 (libgthread); mediapipe (Form pose) initializes an EGL/GLES
# context even on CPU, so it needs libgl1 (libGL.so.1) + libegl1 (libEGL.so.1) + libgles2 (libGLESv2.so.2);
# ffmpeg ensures robust .mov/h264 decode; curl + ca-certificates fetch the pose model below.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libglib2.0-0 libgl1 libegl1 libgles2 ffmpeg curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .
RUN pip install ".[api,form]"
RUN mkdir -p /data

# Form (pose) support: fetch the heavy pose model at build time and pin it by sha256 (NEVER committed to the
# repo). The "latest" URL currently serves this exact sha; if Google ever republishes it, the build fails here
# loudly rather than shipping an unverified model. Baked into the image (read-only, always present — unlike the
# ephemeral /tmp DATA_ROOT). lanesight_core/form/pose.py re-verifies the same sha at load.
RUN mkdir -p /app/models \
 && curl -fsSL "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task" \
      -o /app/models/pose_landmarker_heavy.task \
 && echo "64437af838a65d18e5ba7a0d39b465540069bc8aae8308de3e318aad31fcbc7b  /app/models/pose_landmarker_heavy.task" | sha256sum -c -
ENV LANESIGHT_POSE_MODEL=/app/models/pose_landmarker_heavy.task

# Secrets come from the host as env vars (Cloud Run secrets / fly secrets), read by lanesight_api/config.py:
#   LANESIGHT_DB_URL  LANESIGHT_SERVICE_ROLE  LANESIGHT_JWT_SECRET
# Cloud Run: also set LANESIGHT_SYNC_JOBS=1 (run analysis inline — request-scoped CPU).
# Do NOT set LANESIGHT_API_DEV or LANESIGHT_FORCE_MEMORY in prod (real Supabase auth only).
# Shell form so $PORT (Cloud Run injects 8080; overridable) is honored; defaults to 8080 for Fly/local.
EXPOSE 8080
CMD exec uvicorn lanesight_api.app:app --host 0.0.0.0 --port ${PORT:-8080}

# Form analysis is ENABLED (mediapipe + baked pose model above). mediapipe adds image size + build time; if a
# form clip's RAM peak exceeds the Cloud Run memory, raise --memory on deploy (re-benchmark after enabling).
