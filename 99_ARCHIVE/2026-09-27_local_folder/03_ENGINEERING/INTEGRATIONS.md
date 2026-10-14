# LaneSight Integrations
Status: STRATEGIC / DISCOVERY  
Version: 1.0  
Last Updated: 2026-09-27  
Owner: Shayne  
Supersedes: —

## Principle
Own the Bowler Profile and intelligence layer; integrate authoritative external data where official access permits.

## Adapter families
- SensorAdapter
- ExternalBowlingDataAdapter
- ScoringAdapter
- Membership/Sanctioning adapter

## Strategic targets
- USBC: membership status/renewal path and sanctioned records where officially supported
- LeaguePals: league schedule/team/standings/results where supported
- LaneTalk: scoring/session/center-derived data where supported
- Center scoring systems: automatic score ingestion where partnerships/APIs permit
- Specto: benchmark/validation, not runtime dependency

## Rules
- Never assume API availability.
- Do not make unofficial scraping a core dependency.
- Preserve external IDs, source, season/scope, authority and retrieval timestamp.
- Degrade gracefully when a provider is disconnected.
