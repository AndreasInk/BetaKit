# AGENTS.md

## Mission
BetaKit is an open source SwiftUI package that helps TestFlight beta testers share better feedback with less friction.

## What to optimize for
- Fast, low-effort tester feedback capture
- Clear and respectful UI copy
- Reliable behavior in TestFlight and debug builds
- Safe defaults for package consumers

## Repository basics
- Package name: `BetaKit`
- Main source target: `Sources/BetaKIt`
- Tests: `Tests/BetaKItTests`
- Minimum platforms:
  - iOS 17+
  - macOS 14+

## Local commands
- Build: `swift build`
- Test: `swift test`

## Implementation notes
- Keep new UI components small and composable.
- Preserve public API stability unless a breaking change is intentional and documented.
- Prefer platform-safe SwiftUI color/material usage that compiles on both iOS and macOS.
- If adding TestFlight-specific behavior, guard platform or runtime assumptions explicitly.

## PR checklist
- `swift build` passes.
- `swift test` passes.
- README is updated for user-facing behavior changes.
- Any new public API is documented with a short usage example.
