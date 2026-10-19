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
- `Assets/`: the logo in light and dark appearances, rendered from the skill
  icon in [skill-cli/.github](https://github.com/skill-cli/.github/blob/master/DESIGN.md),
  and the README terminal demo in light and dark appearances under
  [Assets/Demo/](Assets/Demo/), with its recording, provenance, and design recipe

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

## References

- [CLI](Reference/CLI.md): commands, output, state, and JSON schemas
- [Release](Reference/Release.md): core dependency, version, signed publication, and tap validation
- [README demo](Reference/ReadmeDemo.md): recording and rendering the terminal
  session
