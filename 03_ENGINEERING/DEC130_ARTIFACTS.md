# DEC-130 artifact manifest

Trained checkpoints + Core ML exports with sha256 + dual backup (local `backup/` + gs bucket).

| artifact | sha256 | size(MB) | local backup | gs | note | ts |
|---|---|---|---|---|---|---|
| ball_centernet.pt | `7a88ac186e6f560bf5597c376856213c5066892fc689e819e094d6f4294d383a` | 23.4 | /Users/shaynel/LaneSightData/dec130/backup/ball_centernet.pt | gs://project-fd28bc3f-a844-43c2-a1c_cloudbuild/dec130/ball_centernet.pt | v3 unified ball+lane, val_recall 0.969 lane_mae 0.025, CoreML 1.8ms | 2026-11-14 09:30 |
| BallLaneDetector.mlpackage | `a6ae08984d06daeaeadee98a8df41600b3f2f660194b2f18f49adc535450304c` | 11.7 | /Users/shaynel/LaneSightData/dec130/backup/BallLaneDetector.mlpackage | gs://project-fd28bc3f-a844-43c2-a1c_cloudbuild/dec130/BallLaneDetector.mlpackage | v3 unified ball+lane, val_recall 0.969 lane_mae 0.025, CoreML 1.8ms | 2026-11-14 09:30 |
