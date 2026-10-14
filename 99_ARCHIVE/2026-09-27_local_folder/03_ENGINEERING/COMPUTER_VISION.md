# LaneSight Computer Vision
Status: WORKING CANONICAL  
Version: 1.0  
Last Updated: 2026-09-27  
Owner: Shayne  
Supersedes: —

## First environment
Stable phone/tripod directly behind bowler/lane; entire lane visible; target 1080p/60fps where practical.

## Pipeline
Video → lane geometry → ball detection → frame tracking → homography → board/distance coordinates → smoothed trajectory → metrics.

## Trajectory
`P_i=(t_i,x_i,y_i)` with x=board and y=feet downlane.

## Geometry references
Lane width ~41.5 in, 39 boards, arrows ~15 ft, foul line to headpin ~60 ft. Validate exact geometry assumptions in implementation.

## Metrics
Launch board/angle, arrow board, speed, breakpoint board/distance, entry board/angle, pin result.

## Progression
Tripod → handheld → lightly moving POV → normal head movement POV → difficult lighting/occlusion → varied centers.

## Validation
Manually annotate early controlled data. Reserve locked test data. Compare against sensor/Specto/trusted references using MAE, median, p90, bias and failure rate.
