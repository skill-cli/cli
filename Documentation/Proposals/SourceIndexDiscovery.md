# Source Index Discovery

## Status

Draft

## Problem

The production CLI currently requires callers to provide an explicit local path,
GitHub/GitLab shorthand, URL, or well-known source. That keeps the command
surface deterministic, but it does not help users discover suitable skill
sources when they do not already know where a skill lives.

## Boundary

This proposal does not reserve a public command name and does not change the
current CLI reference. Any future surface must be designed from the repository's
own dependency model:

- `add <source>` mutates project skill dependencies.
- `install` materializes `.agent/skills.resolved`.
- `list <source>` inspects a known source.
- hosted source-index discovery, if added, must remain separate from resolved
  state mutation until the user chooses a concrete source.

## Direction

A future source-index feature should return candidate skill sources with enough
metadata for a caller to decide whether to run `skill add <source>`. It should
not install, update, or alter `.agent/skills.resolved` by itself.

Open design questions:

- source index ownership and trust model
- result metadata shape
- compatibility filtering by agent and host
- validation before converting a result into an `add` source
