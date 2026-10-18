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

`Package.swift` owns the graph. Core follows `master` during development;
[release preparation](../Reference/Release.md) selects a published version
range. This repository has no library target. It does not depend on
`AgentsInstructions` or on the `agents` CLI package.

The CLI owns argument validation, help, version output, JSON report schemas,
terminal rendering, recovery notices, and exit codes. It calls `SkillOperations`
for discovery, add, list, update, restore, removal, initialization, and doctor.
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
| `Sources/CLI/Terminal.swift` | One recovery retry, errors, human output, snapshots, JSON encoding |
| `Sources/CLI/JSONReports.swift` | Versioned CLI report DTOs |
| `Tests/CLITests/CLIFixture.swift` | Isolated homes, local Git sources, subprocess runner, cleanup |
| `Tests/CLITests/ParsingTests.swift` | Option mapping and invalid combinations |
| `Tests/CLITests/ConventionTests.swift` | Recovery, fixture cleanup, file snapshot encoding, terminal sanitization |
| `Tests/CLITests/ExecutableTests.swift` | Lifecycle, help, output schemas, exits, environment isolation |
| `Tests/CLITests/StateBoundaryTests.swift` | Instruction preservation and state ownership through the executable |

## Data Flow and State

Commands parse options, call `SkillOperations`, then render its returned models.
Updates provide a callback that prints full before/after snapshots before core
commits replacements. `install` uses exact locked pins and recipients.

Project state is `.agent/agents.json` and `.agent/agents.resolved`; user state
uses the same filenames under `~/.agents/`. Each scope has a `cache/` directory.
Core owns validation, deterministic encoding, source mirrors, pinned content,
installation paths, locking, transaction journals, and pruning. Read commands
may populate caches. Recovery can restore a consistent generation and asks the
CLI to retry once, with a stderr notice. See core's
[state architecture](https://github.com/agents-tools/core/blob/master/Documentation/Architecture/State.md)
for those invariants and [CLI reference](../Reference/CLI.md) for the command contract.

## Validation and Supporting Artifacts

CLI tests exercise the executable with explicit environments and local Git
fixtures, cleaning up their own roots. Core's tests own resolver, discovery,
artifact, storage, concurrency, and installation algorithm coverage.
CI requires strict formatting, an optimized build, tests, release executable
smoke checks, and a diff check.

`Documentation/Reference/Schemas/` owns JSON schemas. `skills/skill-cli/` is the
bundled companion skill, separate from SwiftPM targets. Formulae and packaging
publication belong to the [Homebrew tap](https://github.com/skill-cli/homebrew-tap).
Decision, migration, and archive documents retain their historical scope.
