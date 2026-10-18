# Contributing

This SwiftPM package owns the `skill` command layer. Keep changes small and
aligned with [package ownership](Documentation/Architecture/Package.md).

## Development Loop

Requires macOS 13 or later and Swift 6.3 or later.

```sh
swift build
env -u CODEX_HOME -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME swift test
swift build -c release
xcrun swift-format lint --strict --configuration .swift-format --recursive Package.swift Sources Tests
git diff --check origin/master
.build/release/skill --version
.build/release/skill --help
```

Strict formatting must produce zero findings. CI runs the release build on
every pull request. Executable tests create local Git sources and isolated
homes; subprocesses use an explicit environment and fixtures clean up on exit.

## Change Guidelines

- Keep parsing, terminal output, recovery presentation, and exit codes in
  `Sources/CLI`; test them in `Tests/CLITests`.
- Port shared command changes from agents-tools/cli, keeping the layout parallel.
- Change reusable behavior and its tests in agents-tools/core. This package
  consumes `AgentsCore` and `AgentsSkills` only.
- Keep instruction state and target files untouched by skill commands.
- Update the CLI reference, schemas, companion skill, and architecture when
  their contracts change. Keep historical records in their owning directories.
- Use Conventional Commits with local signing and one logical change per commit.

Core follows `master` during development. To test an authorized core worktree
without changing the manifest:

```sh
swift package resolve
swift package edit core --path /path/to/core-worktree
swift test
swift package unedit core
```

Restore the published dependency before delivery and validate the resolved
revision. Follow [Releasing skill](Documentation/Reference/Release.md) for
version ranges, version checks, signed tags, releases, and tap validation.

## Pull Requests

Describe the resulting behavior, validation results, and documentation changes.
