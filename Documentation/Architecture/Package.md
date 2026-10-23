# Package Architecture

`skill-cli` builds the `skill` executable, a skills command layer over
[agents-tools/core](https://github.com/agents-tools/core). It uses Swift 6.3,
Swift 6 language mode, and a macOS 13 minimum deployment target.

## Products and Ownership

```text
skill (executable product)
  CLI ──> ArgumentParser
      ├─> AgentsCore
      └─> AgentsSkills ──> AgentsCore
  CLITests ──> CLI
```

`Package.swift` owns the graph and the core revision used during development;
[release preparation](../Reference/Release.md) selects a published version range. This repository has no library target. It does not depend on
`AgentsInstructions` or on the `agents` CLI package.

The CLI owns argument validation, help, version output, JSON report schemas,
terminal rendering, recovery notices, and exit codes. It calls `SkillOperations`
for discovery, add, list, update, restore, removal, initialization, doctor, and
watch subscriptions. `SkillOperations.watchOperations()` supplies skill discovery
and artifact loading to core; watch also reports instruction units without
rendering or installing them.
`AgentsSkills` owns skill behavior; `AgentsCore` owns source identity,
requirements, cache, declaration, resolved state, transactions, recovery, and
agent locations. Instruction declarations, locked records, and target files
remain owned by instruction operations and are preserved by skill operations.

## Source Inventory

The layout parallels `agents-tools/cli` so shared command changes can be ported
mechanically. `skill` flattens the `agents skills` group and uses its optional
named update command for both selected and all-skill updates.

| File | Responsibility |
| --- | --- |
| `Sources/CLI/EntryPoint.swift` | Root command, BuildInfo, parsing, help dispatch, exit status |
| `Sources/CLI/Options.swift` | Scope, agent, discovery, mode, and requirement options |
| `Sources/CLI/SkillCommands.swift` | Add, list, remove, and init commands |
| `Sources/CLI/LifecycleCommands.swift` | Install, update options and command, doctor roots |
| `Sources/CLI/Terminal.swift` | One recovery retry, errors, skill summaries, completions, JSON encoding |
| `Sources/CLI/HumanOutput.swift` | Display paths, item markers and ordering, typed file differences |
| `Sources/CLI/LineDiff.swift` | Unified line diffs, context hunks, empty-file and binary notices |
| `Sources/CLI/SkillRendering.swift` | Skill-relative file grouping, cache-link filtering, recipient completions and inventory |
| `Sources/CLI/WatchCommands.swift` | Subscription add, status, diff, seen, and removal |
| `Sources/CLI/WatchRendering.swift` | Watch summaries, display order, and file diffs |
| `Sources/CLI/WatchReports.swift` | Versioned watch status and diff DTOs |
| `Sources/CLI/JSONReports.swift` | Versioned CLI report DTOs |
| `Tests/CLITests/CLIFixture.swift` | Isolated homes, local Git sources, subprocess runner, cleanup |
| `Tests/CLITests/ParsingTests.swift` | Option mapping and invalid combinations |
| `Tests/CLITests/HumanOutputTests.swift` | Unified diffs, paths, ordering, controls, and multiline diagnostics |
| `Tests/CLITests/HumanExecutableTests.swift` | Readable output, repins, completions, and Git diagnostics |
| `Tests/CLITests/SkillRenderingTests.swift` | Physical cache-link paths through symlinked homes |
| `Tests/CLITests/UpdateReportingTests.swift` | Versions, executable flags, membership, and missing-lock output |
| `Tests/CLITests/SkillOutputExecutableTests.swift` | Shared and divergent diffs, modes, recipients, and recovery |
| `Tests/CLITests/ConventionTests.swift` | Recovery, fixture cleanup, file snapshot encoding, terminal sanitization |
| `Tests/CLITests/ExecutableTests.swift` | Lifecycle, help, output schemas, exits, environment isolation |
| `Tests/CLITests/WatchParsingTests.swift` | Watch options, requirements, default status, and kind filters |
| `Tests/CLITests/WatchExecutableTests.swift` | Watch lifecycle, read-only inspection, errors, recovery, and help |
| `Tests/CLITests/WatchReportTests.swift` | Artifact reports, confirmation identities, and snapshot encoding |
| `Tests/CLITests/StateBoundaryTests.swift` | Instruction preservation and state ownership through the executable |

## Data Flow and State

Commands parse options, call `SkillOperations`, then render its returned models.
Updates provide a callback that renders unified file diffs before core commits
replacements. Human output groups identical skill changes across recipients and
omits cache-link moves. Core's membership rows supply recipients and physical
installation roots for update previews and completion; no separate inventory
read is needed. JSON retains exact snapshots and absolute paths.
`install` uses exact locked pins and recipients.

Project state is `.agent/agents.json`, `.agent/agents.resolved`, and
`.agent/agents.watch`; user state uses the same filenames under `~/.agents/`.
Each scope has a `cache/` directory. Subscriptions live in the declaration;
watch baselines live in `agents.watch`. Both CLIs share these formats.
Watch status and diff may fetch sources but preserve declarations, locks,
baselines, installations, and source working trees.
Core owns validation, deterministic encoding, source mirrors, pinned content,
installation paths, locking, transaction journals, and pruning. Read commands
may populate caches, while doctor only inspects existing state. Mutating
commands recover a consistent generation and retry once with a stderr notice.
Doctor reports pending recovery as an error without changing state. See core's
[state architecture](https://github.com/agents-tools/core/blob/master/Documentation/Architecture/State.md)
for those invariants and [CLI reference](../Reference/CLI.md) for the command contract.

## Validation and Supporting Artifacts

CLI tests exercise the executable with explicit environments and local Git
fixtures, cleaning up their own roots. Core's tests own resolver, discovery,
artifact, storage, concurrency, and installation algorithm coverage.
`scripts/check-parity.py` manually compares lifecycle and watch behavior with a
supplied read-only `agents` checkout, including exact declaration, lock, and baseline
bytes, JSON reports, and normalized human stdout and stderr. It builds an archive
of the reference HEAD in this worktree and cleans its isolated fixtures.
CI requires `policy / policy` and `validate / result`. Package validation covers
strict formatting, tests, a release build, and terminal demo recording checks.
Executable tests own help, version, and usage-error assertions.

`Documentation/Reference/Schemas/` owns JSON schemas. `skills/skill-cli/` is the
bundled companion skill, separate from SwiftPM targets. Formulae and packaging
publication belong to the [Homebrew tap](https://github.com/skill-cli/homebrew-tap).
Decision, migration, and archive documents retain their historical scope.
