# Changelog

User-visible changes are recorded here in Keep a Changelog style. Follow the
family [versioning policy](https://github.com/agents-tools/.github/blob/master/VERSIONING.md)
and the [release checklist](Documentation/Reference/Release.md).
Earlier history is in [GitHub releases](https://github.com/skill-cli/cli/releases).

## [Unreleased]

### Added

- Update previews and completion lines show resolved versions alongside revisions.
- Update previews show executable-mode changes and each agent's added, removed,
  unchanged, or changed-mode membership, including live edit installations with
  no file differences. Missing locks are identified as unrecorded membership.
- Version 1 update JSON adds resolved versions, executable flags, missing-lock
  status, and per-agent before/after membership.

### Changed

- **Breaking**: Requires macOS 26 or later; source builds require Swift 6.3 or
  later. Upgrade macOS before installing and use a compatible Swift toolchain
  when building from source.

### Fixed

- Executable-only updates are displayed and applied even when content hashes or
  revisions are unchanged.
- Update file grouping and recipient completions use the prepared membership
  report, including new recipients and recipients sharing a physical path.

## [0.3.1] - 2026-10-20

Built on agents-tools/core 0.1.1.

### Fixed

- Sources accept typed selectors again, as in
  `skill add larksuite/cli@from:1.0.0@skill:lark-base`: `@branch:`, `@ref:`,
  `@revision:`, `@exact:`, `@from:`, `@minor:`, `@path:`, and `@skill:`.
- Adding a source whose last path component another source already uses, such
  as a second `…/skills` repository, declares it under a prefixed alias like
  `anthropics-skills` instead of failing.

## [0.3.0] - 2026-10-19

### Added

- Watch subscriptions with status, file diffs, and explicit acknowledgement
  through `skill watch add`, `watch diff`, and `watch seen`.
- Unified file diffs for update previews, with readable summaries and paths.

### Changed

- Rebuilt the CLI on shared agents core with `agents.json` declarations and
  `agents.resolved` locks in project `.agent/` or user `~/.agents/`. Skill names
  are positional arguments; updates preview changes before `--apply` writes.
  Existing 0.2 state is not read, and 0.2 installations are never replaced:
  move or remove them, then add sources and watch subscriptions again.
  See [upgrading from 0.2](Documentation/Migrations/From0.2.md).

### Removed

- The 0.2 watch ledger and `review` commands; watch now uses subscriptions.

### Fixed

- Git failures now include concise diagnostics and recovery guidance.
- Adding or installing a skill never replaces a directory, file, or link that
  the scope's lock does not manage, such as a hand-written skill.

[Unreleased]: https://github.com/skill-cli/cli/compare/v0.3.1...master
[0.3.1]: https://github.com/skill-cli/cli/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/skill-cli/cli/compare/v0.2.2...v0.3.0
