# LaneSight MVP Requirements
Status: CANONICAL  
Version: 1.0  
Last Updated: 2026-09-27  
Owner: Shayne  
Supersedes: —

## Goal
Prove bowlers will create and revisit a LaneSight profile because ordinary fixed-camera bowling video produces uniquely useful performance intelligence.

## Must have
- Account/profile creation with minimal onboarding
- Fixed rear-camera video upload/recording
- Manual/assisted lane calibration
- Automatic ball detection and tracking
- Lane-coordinate trajectory reconstruction
- Core metrics where reliable: speed, launch, arrows, breakpoint, entry, pin result
- Intended target and target error
- Confidence and explicit unavailable/failure states
- Annotated replay/top-down path
- Save shot to profile/history
- Select Current Ball
- Basic Arsenal objects
- Optional early sensor synchronization/fusion
- Delete original media / privacy controls

## Should have
- Shareable analysis/replay
- Auto-populated ball factory specs
- Basic deterministic feedback
- Session comparison

## Not MVP
- Full League Mode automation
- Full league management
- Team Lane Management
- USBC renewal
- Direct center scoring integration
- Smart glasses/POV
- Payments/prize funds

## Quality gates
- Speed target: approximately ±0.5 mph vs trusted reference
- Path median: ≤1 board where benchmark quality permits
- Breakpoint: approximately 1–1.5 boards
- Entry board: ≤1 board
- Entry angle: approximately 1 degree
- Strike/non-strike classification: target ≥95%
- Every metric includes confidence/source
