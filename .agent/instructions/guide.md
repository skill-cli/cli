---
description: Keep skill-cli a thin command layer that mirrors the agents CLI and leaves instruction state untouched.
---
# skill-cli Agent Guide

## Command Layer

- This package is a command layer. Keep CLI parsing and terminal behavior in
  `Sources/CLI`; reusable behavior belongs to `AgentsCore` and `AgentsSkills`
  in agents-tools/core.
- Mirror the agents-tools/cli file layout and shared command behavior.
- Call only `SkillOperations`; preserve instruction declarations, locked
  records and target files.
- Keep CLI tests in `Tests/CLITests` with explicit subprocess environments.
- Keep package-domain prefixes out of internal target names unless the package
  boundary stops making that context clear.
- `scripts/check-parity.py` is a manual check.
