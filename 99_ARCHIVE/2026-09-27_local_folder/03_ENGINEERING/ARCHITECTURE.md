# LaneSight Architecture
Status: WORKING CANONICAL  
Version: 1.0  
Last Updated: 2026-09-27  
Owner: Shayne  
Supersedes: —

## Principles
Hardware-agnostic, source-aware measurements, asynchronous analysis, versioned algorithms, adapter-based external integrations.

## Components
- iOS-first mobile client
- web/debug tooling; later league/coach/admin web
- API/backend
- CV/ML analysis service
- object storage for video/clips
- Postgres/Supabase transactional/profile store
- async job queue/workers
- authentication
- recommendation engine
- sensor adapter layer
- external bowling/scoring adapter layer
- native/service TTS for Audio Coach
- observability/model provenance

## Analysis pipeline
`Capture/Upload → Calibration → Lane Geometry → Ball Detection → Tracking → Lane Coordinates → Trajectory → Metrics → Classification → Recommendation → Persist/Profile`

## Important separation
Measurement engine and recommendation engine are separate. Deterministic coaching can ship before learned recommendation models.
