# Changelog

User-visible changes are recorded here in Keep a Changelog style. Follow the
family [versioning policy](https://github.com/agents-tools/.github/blob/master/VERSIONING.md)
and the [release checklist](Documentation/Reference/Release.md).
Earlier history is in [GitHub releases](https://github.com/skill-cli/cli/releases).

## [Unreleased]

### Added

- Watch subscriptions with status, file diffs, and explicit acknowledgement
  through `skill watch add`, `watch diff`, and `watch seen`.
- Unified file diffs for update previews, with readable summaries and paths.

### Changed

- Rebuilt the CLI on shared agents core with `agents.json` declarations and
  `agents.resolved` locks in project `.agent/` or user `~/.agents/`. Skill names
  are positional arguments; updates preview changes before `--apply` writes.
  Existing 0.2 state is not read: add sources and watch subscriptions again.
  See [upgrading from 0.2](README.md#upgrading-from-02).

### Removed

- The 0.2 watch ledger and `review` commands; watch now uses subscriptions.

### Fixed

- Git failures now include concise diagnostics and recovery guidance.

[Unreleased]: https://github.com/skill-cli/cli/compare/v0.2.2...master
