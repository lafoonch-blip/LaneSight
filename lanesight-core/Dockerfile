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

# opencv-python-headless needs libglib2.0-0 (libgthread); ffmpeg ensures robust .mov/h264 decode.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libglib2.0-0 ffmpeg \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .
RUN pip install ".[api]"
RUN mkdir -p /data

# Secrets come from the host as env vars (fly secrets set ...), read by lanesight_api/config.py:
#   LANESIGHT_DB_URL  LANESIGHT_SERVICE_ROLE  LANESIGHT_JWT_SECRET
# Do NOT set LANESIGHT_API_DEV or LANESIGHT_FORCE_MEMORY in prod (real Supabase auth only).
EXPOSE 8080
CMD ["uvicorn", "lanesight_api.app:app", "--host", "0.0.0.0", "--port", "8080"]

# ---- FOLLOW-UP: enable Form analysis ----
# 1) change `pip install ".[api]"` -> `pip install ".[api,form]"`
# 2) put the model on the volume at /data/models/pose_landmarker_heavy.task (or bake it in), and confirm the
#    pose backend's model path resolves to $LANESIGHT_DATA/models.
# mediapipe pulls more libs + size; keep it out of the first deploy.
