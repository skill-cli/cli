# Package Architecture

## Scope / Purpose

This document states the current package structure for `skill-cli`, the SwiftPM
package that builds the `skill` executable.

## Context / Boundaries

The package is a Swift-native implementation for agent skill installation and
managed source watching. The supported agent scope is Codex, Claude Code,
Cursor, Gemini CLI, and OpenCode.

Source-based skill bundles are in scope, including repository layouts such as
`skills/<name>/SKILL.md`. Package-manager installation of a third-party CLI
binary remains that CLI's responsibility; this package installs and manages
skill files only.

## Constraints

- The package name is `skill-cli`.
- The executable product name is `skill`.
- Internal target names avoid repeating the package domain.
- Swift language mode is Swift 6.
- Reusable behavior belongs in `Core`.
- CLI parsing and terminal concerns belong in `CLI`.

## Current Structure

```text
skill-cli/
  Package.swift
  skills/
    skill-cli/
      SKILL.md
      agents/openai.yaml
  Sources/
    Core/
      AgentRegistry.swift
      Discovery.swift
      InstallLock.swift
      Installer.swift
      RuntimeService.swift
      SourceParser.swift
      SourceRequirement.swift
      WatchLedger.swift
      WellKnownProvider.swift
      ...
    CLI/
      AddCommand.swift
      CLIOptions.swift
      CLIOutput.swift
      EntryPoint.swift
      ExperimentalInstallCommand.swift
      InitCommand.swift
      ListCommand.swift
      RemoveCommand.swift
      UpdateCommand.swift
      WatchCommands.swift
  Tests/
    CoreTests/
      *BehaviorTests.swift
      CLISurfaceTests.swift
      CoreTestSupport.swift
      InstallWorkflowTests.swift
      SourceAndDiscoveryWorkflowTests.swift
      WatchCLITests.swift
      WatchInstallWorkflowTests.swift
      WatchServiceBehaviorTests.swift
      WellKnownArtifactTests.swift
```

`Package.swift` defines:

- product `skill`
- target `Core`
- executable target `CLI`
- test target `CoreTests`

Homebrew formulae and tap release instructions belong in the dedicated Homebrew
tap repository, not in this source repository.

The repository-bundled `skills/skill-cli` package is a product-facing companion
skill for this CLI. It is maintained with the source package because it
documents and exercises the supported command surface, but it remains separate
from SwiftPM targets and release automation.

## Key Principles

- Implement behavior in tested Swift core types before exposing it through CLI
  flows.
- Keep terminal UI, prompts, and process exit behavior out of `Core`.
- Keep package structure owned by the Swift package boundary and current
  command surface.
- Prefer explicit source verification policy over default telemetry or remote
  advisory coupling.
- Keep the skill source registry SPM-inspired, with stable first-party lock
  types instead of depending on SwiftPM internals.

## Registry Design

The install registry follows SwiftPM's package-resolution philosophy without
using SwiftPM runtime model types. `SourceRequirement` records first-party
requirement intent such as branch, revision, exact version, lower-bound
version, minor range, and explicit range. `SourcePin` records source identity,
location, requirement, and resolved state; `PinnedSkill` records the installed
skill path and content hash; `InstallationPin` records the agent, scope, mode,
and target path.

This keeps source identity, restore, update, and diff behavior deterministic
while preserving skill-specific state that SwiftPM package graph types do not
model, such as agent installations, watched review baselines, and well-known
artifact digests.

Resolved state, source cache, canonical installed copies, and agent projections
are separate storage concerns. Project scope stores resolved state in
`.agent/skills.resolved`, source checkouts in `.agent/cache`, and canonical
installed skills in `.agents/skills`. User scope stores resolved state in
`$XDG_STATE_HOME/skills/skills.resolved` or `$HOME/.agents/skills.resolved`,
source checkouts in `$XDG_CACHE_HOME/skill-cli`, `$HOME/Library/Caches/skill-cli`
on macOS, or `$HOME/.cache/skill-cli` on other platforms, and default link-mode
canonical installed skills in `$HOME/.agents/skills`. Agents whose configured
project skill directory is `.agents/skills` use the canonical user directory
directly; native-only agents receive a projection in their own skill directory.
Agent-facing skill directories expose installed skills; they do not own source
checkout state.

The schema is SPM-inspired rather than SwiftPM-backed by design:

- `PackageDescription` is a manifest DSL, not the runtime model for managed
  skills.
- SwiftPM package model, workspace, package graph, and pin-store types are
  toolchain-coupled internals and are not stable CLI business models.
- SwiftPM models package dependency graphs; this CLI models skill sources,
  selected skill paths, agent install targets, watch cursors, review baselines,
  content hashes, and well-known artifact digests.
- user-facing lock and ledger files remain under this package's schema control
  instead of inheriting SwiftPM internal evolution.

## Source Syntax

The preferred source syntax is Swift-native typed shorthand:

```text
owner/repo@branch:main
owner/repo@branch:main@path:skills/example
owner/repo@from:1.2.0@skill:example
owner/repo@revision:abc123@path:skills/example
```

Canonical flags follow SwiftPM-style spelling:

```text
--branch <name>
--revision <sha>
--exact <version>
--from <version>
--up-to-next-minor-from <version>
--from <version> --to <version>
```

The legacy `owner/repo#ref@skill` shorthand remains accepted for migration but
is not the recommended syntax.

## Managed Watch Model

Managed mode uses the same source parser, requirement resolver, discovery, path
safety, and lock primitives as install mode. `add --watch-only` writes only the
watch ledger; `add --watch` writes the watch ledger and installs from the
watch baseline or reviewed commit. Re-running `add --watch` upserts by source
identity and requirement, merges paths, refreshes `currentHead`, and preserves
review cursors.

Requirement changes are explicit. `--replace-requirement` resets the watched
baseline and path review cursors and records a ledger event; it never marks the
new head reviewed by default.

## Cross-cutting Concerns

- source parsing for local paths, GitHub repositories, and well-known skill
  sources
- source requirement parsing and SemVer tag resolution
- install behavior for project and user locations
- agent-specific prompt and skill layout differences
- watch ledger, review cursor, and install baseline state
- migration compatibility where it matches this scope

## Risks / Known Gaps

- Hosted source index discovery, hosted audit, telemetry, unsupported agents,
  and third-party CLI binary management are intentionally outside the package
  scope.
- A hosted marketplace index is not required for production use when callers
  provide an explicit source URL or owner/repo shorthand.
- Interactive prompt UI is not the Swift CLI readiness gate; noninteractive
  parsing, explicit flags, and deterministic state transitions are the tested
  contract.
- Watch state is project-local in `.agent/skills-state.json`; it is readable
  and diffable but remains CLI-owned, not a hand-edited configuration API.

## Related Decisions

- `../Decisions/CLIIdentity.md`
- `../Decisions/SPMInspiredRegistry.md`
- `../Decisions/SwiftStyleFlagSurface.md`
