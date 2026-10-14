# LaneSight Data Model
Status: WORKING CANONICAL  
Version: 1.0  
Last Updated: 2026-09-27  
Owner: Shayne  
Supersedes: —

## Identity
User, BowlerProfile, ExternalIdentity, ExternalDataConnection.

## Equipment
BallModel, UserBall, BallConfiguration, SurfaceEvent, BallMaintenanceEvent.

## Sessions & shots
Session, SessionLane, LeagueSession, DeliveryEvent, Shot, ShotIntent, VideoAsset, Calibration, TrajectoryPoint, PinState.

## Measurements
Measurement(value, unit, source, confidence, algorithm/model version, timestamp), MeasurementSource, SensorDevice, SensorShot.

## Coaching
UserShotFeedback, ShotClassification, Observation, Recommendation, RecommendationOutcome, TransitionState.

## Recognition/team
SessionIdentity, UserMatchDecision, TeamLaneState, TeamLaneObservation.

## League/external
League, LeagueSeason, Team, TeamMembership, LeagueEvent, Standing, ScoreRecord, MembershipRecord, SanctionedMetric, ExternalMetric.

## Non-negotiable modeling rules
- Never overwrite historical ball configuration/surface.
- External metrics retain source, season/scope and retrieval time.
- League average and sanctioned average are different records.
- Every shot retains lane, timestamp, ball/configuration and source-aware measurements.
