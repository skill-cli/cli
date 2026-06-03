---
name: skill-cli
description: Manage agent skills with the skill CLI. Use when a user asks how to install, restore, list, update, remove, watch, review, or migrate skills with the `skill` command; needs help choosing project versus user scope, selecting agents, using local or remote skill sources, understanding `skills.resolved`, or replacing a direct-directory installer workflow.
metadata:
  short-description: Use the skill CLI to manage agent skills
  requires:
    bins: ["skill"]
  cliHelp: "skill --help"
---

# skill-cli

Use the installed `skill` executable to manage agent skills. This is the
companion skill for `skill-cli`, the Swift-native CLI that installs, restores,
lists, updates, removes, watches, and reviews skill sources.

## Operating Rules

- Use `skill` commands for skill lifecycle operations.
- Do not run legacy installer helper scripts.
- Do not write directly to an agent-specific skills directory.
- Prefer user scope when the user asks for personal or agent-wide skills.
- Use project scope when the user asks for repo-local or workspace-local skills.
- Target Codex when the user does not name an agent.
- Pass explicit agents with `--agent`.
- Use `--agent *` only when the user explicitly asks to target every supported
  agent.
- Use `--all` only when the user explicitly asks to install, list, update, or
  remove all matching skills.

## Verify CLI

Before changing skill state, check that the CLI is available:

```bash
skill --version
skill --help
```

If `skill` is missing, ask the user to install it first:

```bash
brew install skill-cli/tap/skill-cli
```

## Scopes And Agents

Use project scope for repo-local installs:

```bash
skill add <source> --scope project --agent codex --skill <skill-name>
skill install --scope project
skill list --scope project
```

Use user scope for personal installs shared across workspaces:

```bash
skill add <source> --scope user --agent codex --skill <skill-name>
skill install --scope user
skill list --scope user --agent codex
```

Supported agents are `codex`, `claude-code`, `cursor`, `gemini-cli`, and
`opencode`. Use `--agent *` only on explicit request.

## Sources

Prefer explicit sources:

```bash
skill list <owner>/<repo>
skill list <owner>/<repo> --path <path/to/skill-or-container>
skill list <local-path> --path <path/to/skill-or-container>
```

Use SwiftPM-style requirements when the user needs a non-default revision:

```bash
skill add <owner>/<repo> --branch <name> --skill <skill-name>
skill add <owner>/<repo> --revision <sha> --skill <skill-name>
skill add <owner>/<repo> --from <version> --skill <skill-name>
```

Typed shorthand is also valid:

```bash
skill add owner/repo@branch:main@skill:name
```

## List

List installable skills from a source:

```bash
skill list <source>
```

List OpenAI curated skills:

```bash
skill list openai/skills --path skills/.curated
```

Use JSON only when a scriptable result is needed:

```bash
skill list <source> --json
```

List managed installed skills:

```bash
skill list
skill list --scope user --agent codex
skill list --scope user --agent codex --skill <skill-name>
```

Scan the filesystem, including unmanaged skills:

```bash
skill list --all --scope user --agent codex
skill list --all --scope user --agent codex --skill <skill-name>
```

If the source contains multiple skills and the user did not name one, list the
candidates and ask which ones to install.

## Add

Add or change a skill dependency and materialize it for the selected scope and
agents:

```bash
skill add <source> --scope user --agent codex --skill <skill-name>
```

Install an OpenAI curated skill:

```bash
skill add openai/skills --path skills/.curated --scope user --agent codex --skill <skill-name>
```

Install from a repository path:

```bash
skill add <owner>/<repo> --path <path/to/skill-or-container> --scope user --agent codex --skill <skill-name>
```

Install from a local checkout:

```bash
skill add <path> --path <path/to/skill-or-container> --scope user --agent codex --skill <skill-name>
```

Install all skills in a source or container only when requested:

```bash
skill add <source> --path <path/to/container> --scope user --agent codex --all
```

## Install

Restore managed installs from resolved state:

```bash
skill install --scope user
```

This is the equivalent of materializing the selected scope's resolved skill
state into canonical skill directories and agent projections.

## Update

Check managed updates without applying them:

```bash
skill update --scope user
```

Apply an update for a named skill:

```bash
skill update <skill-name> --scope user --apply
```

Use `--all` only when the user explicitly asks to update every managed skill.

## Remove

Remove a managed skill for Codex:

```bash
skill remove <skill-name> --scope user --agent codex
```

Remove for every recorded agent only when requested:

```bash
skill remove <skill-name> --scope user --agent *
```

## Watch And Review

Use watch mode only when the user asks for managed source review or reviewed
source updates:

```bash
skill add <source> --watch-only --scope user --skill <skill-name>
skill add <source> --watch --scope user --skill <skill-name>
skill diff <source> --watch --path <path/to/skill>
skill review check <source> --watch --path <path/to/skill>
skill review done <source> --watch --path <path/to/skill> --note "reviewed"
skill update <source> --from-watch --scope user --apply
```

Watch state is CLI-owned. Do not hand-edit watch state files unless the user
explicitly asks for low-level repair and the file format has been inspected.

## State Model

- Resolved state records source pins, selected skills, install targets, and
  content hashes.
- Project scope uses project-local resolved state and `.agents/skills`.
- User scope uses user resolved state and canonical `~/.agents/skills`.
- Agent-specific projections are derived install surfaces, not source state.
- `skill install` restores from resolved state when files were deleted or when
  a new machine needs to materialize existing pins.

## Communication

- Before changing skill state, state the exact source, scope, agent, and
  selected skill names.
- After a successful install, update, restore, or remove, tell the user that
  Codex may need a restart or new session to pick up changed skills.
- If a command fails, report the exact command and the relevant error. Do not
  hide retries or silently switch to direct filesystem edits.
- If the user asks for an unsupported command, explain the supported `skill`
  command that matches the intent instead.

## Boundaries

This skill manages skill files through `skill`. It does not manage Codex
plugins, MCP servers, Homebrew formula release, GitHub releases, App Store
submissions, or package-manager installation of third-party CLI binaries.
