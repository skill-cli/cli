# Contributing

This repository is a SwiftPM package. Keep changes small, tested, and aligned
with the documented package boundaries.

## Development Loop

```bash
swift build
swift test
swift run skill --version
```

## Change Guidelines

- Put reusable behavior in `Sources/Core`.
- Put command parsing, process IO, and terminal behavior in `Sources/CLI`.
- Add tests under `Tests/CoreTests` for core behavior before wiring CLI flows.
- Update `Documentation/Architecture/*` when the current structure changes.
- Add a decision record under `Documentation/Decisions/*` when a change locks
  in a meaningful direction.

## Pull Requests

Before opening a pull request, include:

- a short description of the behavior change
- validation commands and results
- documentation updates when command behavior or package structure changes
