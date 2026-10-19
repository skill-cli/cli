# skill-cli Agent Guide

Read `README.md` first for repository purpose, command surface, and development
entry points.
Follow the family [change flow](https://github.com/agents-tools/.github/blob/master/MAINTENANCE.md#change-flow).
`CONTRIBUTING.md` owns the local validation loop and required CI contexts.

## First-Principles Work

- Name the behavior, root cause, invariant, owner, data flow, and validation
  before changing reusable files.
- Change the owning layer, not the nearest convenient file.
- Keep changes traceable to the request, source evidence, or owning invariant.
- Validate with package-local checks when behavior changes.

## Task Route

- For documentation placement, read `Documentation/README.md` before editing.
- For current package structure, read `Documentation/Architecture/README.md`
  and the relevant architecture files.
- For unresolved design work, use `Documentation/Proposals/*`.
- For durable rationale, use `Documentation/Decisions/*`.
- For migration notes, use `Documentation/Migrations/*`.
- For retired material, use `Documentation/Archive/*`.
- For supporting details and examples, use `Documentation/Reference/*`.
- For GitHub-facing collaboration files, use `.github/` and root governance
  files.

## Authority

- `AGENTS.md` is the agent guide for repository work.
- `README` files index scope and placement.
- `Documentation/Architecture/*` states current truth.
- `Documentation/Proposals/*` is design-in-progress.
- `Documentation/Decisions/*`, `Documentation/Migrations/*`, and
  `Documentation/Archive/*` are history.
- `.github/*` is GitHub-facing governance and workflow metadata.

## Boundary Guardrails

- Do not promote machine-local paths, one-run state, fixture-only values, or
  temporary execution state into reusable docs, scripts, templates, or
  automation.
- If a value changes by input or environment, pass it in, configure it, derive
  it, or link to the owning artifact.
- Keep CLI parsing and terminal behavior in the CLI owner, and reusable logic
  in agents-tools/core.

## Operating Notes

- Keep package-domain prefixes out of internal target names unless the package
  boundary stops making that context clear.
- Keep CLI parsing and terminal behavior in `Sources/CLI`.
- This package is a command layer; reusable behavior belongs to
  `AgentsCore` and `AgentsSkills` in agents-tools/core.
- Mirror agents-tools/cli file layout and shared command behavior.
- Call only `SkillOperations`; preserve instruction declarations, locked
  records, and target files.
- Keep CLI tests in `Tests/CLITests` with explicit subprocess environments.
- Run the development-loop checks in `CONTRIBUTING.md` before handing off
  behavior or workflow changes, including `swift test` with agent configuration
  overrides unset. Keep policy, shared package validation, release executable
  smoke checks, and presentation validation passing.
