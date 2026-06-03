# Documentation

This directory indexes repository-native documentation for `skill-cli`.

## Areas

- `Architecture/`: current truth for package structure and documentation
  placement
- `Proposals/`: design-in-progress and open alternatives
- `Decisions/`: accepted decisions and rationale
- `Migrations/`: transition and cutover records
- `Archive/`: retired or superseded material kept for record
- `Reference/`: supporting reference material and examples

Target-level API documentation belongs with the SwiftPM target it documents,
normally under `Sources/<Target>/<Target>.docc/`. Link to those catalogs from
this index when present, but do not move them under `Documentation/` by
default.

## Placement Rules

- Put current canonical guidance in `Architecture/`.
- Put unresolved changes and alternatives in `Proposals/`.
- Put historical records in `Decisions/`, `Migrations/`, and `Archive/`.
- Put supporting reference material in `Reference/`.
- Keep DocC catalogs with their SwiftPM targets.
- Keep GitHub-facing governance in `.github/`, not here.
