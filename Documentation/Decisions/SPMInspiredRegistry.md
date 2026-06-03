# SPM-Inspired Skill Registry

## Status

Accepted

## Design

`skill-cli` owns a first-party registry and lock schema for skills
installed from local paths, source-control repositories, and well-known skill
indexes. The model uses SwiftPM-style source identity, requirement intent, and
resolved pin state, but it is a skill registry rather than a package dependency
graph.

Registry state is explicit:

- `LockFile` owns lock-file versioning and source pins.
- `SourceRequirement` owns caller intent for branch, revision, exact version,
  lower-bound version, minor range, compatibility ref, and explicit version
  range.
- `SourcePin` owns source identity, kind, location, requirement, and resolved
  pin state.
- `PinState` owns source-control and artifact state such as revision, branch,
  ref, version, and digest.
- `PinnedSkill` owns skill identity, name, source-relative path, and content
  hash.
- `InstallationPin` owns scope, agent, install mode, and installed path.

## Invariants

- source identity is stable and separate from the user-supplied location
- requirement intent is separate from resolved pin state
- restore and update operate from durable lock state
- lock output is deterministic, diffable, and user-visible
- version requirements can resolve against source-control tags
- a repository can contain multiple independently installable skills
- a selected skill path is part of the install decision
- install state records agent, scope, mode, target path, and content hash
- watch state records baseline, current head, path-scoped cursors, and external
  review closeout receipt data
- well-known sources can carry digest-verified `SKILL.md` or archive artifact
  state
- install lock and watch ledger share source primitives but remain separate
  stores because installation and review are different lifecycle concerns

## SwiftPM Boundary

SwiftPM provides useful vocabulary for source requirements and pinned state.
SwiftPM internal runtime types are not part of this CLI's business model.
`PackageDescription`, workspace, package graph, resolver, and pin-store
implementation types remain outside the registry.

The CLI schema models skill-specific state that SwiftPM package models do not:
selected skill paths, agent install targets, watch cursors, reviewed baselines,
content hashes, and well-known artifact digests.

## Consequences

- Lock files remain stable and controlled by `skill-cli`.
- The model can represent multi-skill repositories and multi-agent installs
  without forcing skill state into package dependency concepts.
- Install lock and watch ledger can share source pin and requirement
  primitives while preserving separate install and review-cursor stores.
- The CLI can preserve SwiftPM-like determinism for restore/update/diff while
  retaining skill-specific semantics.
- Version requirements can be resolved from git tags without importing
  SwiftPM's package graph or resolver internals.
- Future SwiftPM changes do not silently change the user-facing skill lock
  schema.
- The registry can be stricter and more auditable than an ad hoc marketplace or
  opaque package cache because every install is tied back to source identity,
  resolved state, selected path, and agent target state.
- If versioned skill sources or dependency solving become product requirements,
  they should be added through this schema rather than by importing SwiftPM
  workspace internals.

## Related Documentation

- Related architecture documentation: `../Architecture/Package.md`
- Owning code: `../../Sources/Core/InstallLock.swift`
