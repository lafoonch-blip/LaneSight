# LaneSight Sensor Fusion
Status: WORKING CANONICAL  
Version: 1.0  
Last Updated: 2026-09-27  
Owner: Shayne  
Supersedes: —

## Strategy
Sensor fusion is early and optional. Vision provides accessible path/reaction data; sensors provide trusted release telemetry when available.

## Adapter contract
Normalize when available: speed, RPM, axis rotation, axis tilt, loft, event/release timestamp and confidence.

Potential adapters: F5Adapter, WitseeAdapter, FutureSensorAdapter. Do not make the core domain model vendor-specific.

## Synchronization
Initial matching uses release/event timestamps within a tolerance window. One `Shot` can contain measurements from multiple sources.

## Source awareness
Example: RPM can be SENSOR with high confidence while BREAKPOINT is LANESIGHT_VISION. Overlapping speed values should be retained for validation rather than destroying one source.

## Development value
Synchronized sensor/video sessions create labeled development data. Do not train a broad production model only on one bowler.
