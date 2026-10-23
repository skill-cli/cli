# Contributing

This SwiftPM package owns the `skill` command layer. Keep changes small and
aligned with [package ownership](Documentation/Architecture/Package.md).
Follow the family [change flow](https://github.com/agents-tools/.github/blob/master/MAINTENANCE.md#change-flow)
for commits, review, and delivery.

## Development Loop

Requires macOS 26 or later and Swift 6.3 or later.

```sh
swift build
env -u CODEX_HOME -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME swift test
swift build -c release
swift format lint --strict --configuration .swift-format --recursive Package.swift Sources Tests
```

Strict formatting must produce zero findings. Executable tests create local
Git sources and isolated homes; subprocesses use an explicit environment and
fixtures clean up on exit. Help, version, and usage-error assertions live in
`Tests/CLITests/ExecutableTests.swift`. For workflow changes, run `actionlint`.
When changing presentation assets, follow the
[local rendering checks](Documentation/Reference/ReadmeDemo.md#local-rendering).

## CI

The family [maintenance declaration](https://github.com/agents-tools/.github/blob/master/MAINTENANCE.md#activation-and-required-checks)
owns the required contexts and their activation. The callers in
`.github/workflows/` pin the shared workflows to a reviewed full commit SHA.

Required checks are exactly `policy / policy` and `validate / result`.

| Context | Validation |
| --- | --- |
| `policy / policy` | Commit identity and signatures, Conventional Commit subjects, PR titles, and added-line policy |
| `validate / result` | Aggregate of strict formatting, tests, release build, and terminal demo recording checks using `.github/swift-package.json` |

The shared workflows live in
[agents-tools/github-workflows](https://github.com/agents-tools/github-workflows).
The single compiler entry uses Xcode 26.6 on macOS 26. Formatting covers
`Package.swift`, `Sources`, and `Tests` with `.swift-format`.
The demo job builds `skill`, re-records `.github/assets/terminal/script.yml`,
and uploads the regenerated `recording.json` on drift for review and commit.

Render and check the terminal SVGs and social preview locally with the
`github-readme-design` toolchain against
[skill-cli/.github's DESIGN](https://github.com/skill-cli/.github/blob/master/DESIGN.md),
fonts, and catalog. Follow [presentation reproduction](Documentation/Reference/ReadmeDemo.md)
for the toolchain reference and asset locations.

Policy and CI run on branch pushes and on opened, synchronized, or reopened
pull requests. Title edits rerun only policy. Both callers support manual
dispatch; manual policy runs validate the selected head commit. These are
development checks; follow the release checklist for release validation.
Weekly Dependabot PRs cover Swift packages and GitHub Actions.

### Shared command parity

This is a manual check. To compare the shared command contract with a read-only
`agents` checkout:

```sh
python3 scripts/check-parity.py --agents-package /path/to/agents-tools/cli
```

Build `skill` first. The runner archives the reference checkout's HEAD and builds
`agents` under this worktree's `.build/agents`, uses isolated environments, and
removes its `.agent/parity` fixtures. It compares lifecycle and watch state bytes,
JSON reports, human stdout and stderr, and watch help across project/user scope
and link/copy installations with multiple recipients. Human comparisons normalize
client paths and command names; install compares the skill operation's output.
Scenarios include repins, shared diffs, controls, empty files, binary files,
links, executable-mode changes, removals, and multiline Git diagnostics.

## Change Guidelines

- Keep parsing, terminal output, recovery presentation, and exit codes in
  `Sources/CLI`; test them in `Tests/CLITests`.
- Port shared command changes from agents-tools/cli, keeping the layout parallel.
- Change reusable behavior and its tests in agents-tools/core. This package
  consumes `AgentsCore` and `AgentsSkills` only.
- Keep instruction state and target files untouched by skill commands.
- Update the CLI reference, schemas, companion skill, and architecture when
  their contracts change. Keep historical records in their owning directories.

Core is pinned by revision during development. To test an authorized core worktree
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
