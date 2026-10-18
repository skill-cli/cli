---
name: skill-cli
description: Use the skill CLI to add, list, restore, update, remove, initialize, or diagnose agent skills from declared sources in project or user scope.
---

# skill CLI

Use the installed `skill` executable (`swift-skill` is equivalent) to manage
skills for Codex, Claude Code, Cursor, Gemini CLI, and OpenCode. Run
`skill --version` and `skill <command> --help` to inspect the available build.
These instructions describe the 0.3 command surface.

## Choose Scope and Recipients

Project scope is the default and uses the current directory. Change directory
to the intended project before running commands. Use `--scope user` for HOME's
shared state. Declaration and lock files are `agents.json` and `agents.resolved`
in project `.agent/` or user `~/.agents/`; core owns their validation and writes.
Instruction declarations, locked records, and target files stay untouched.

For add, repeat `--agent` to choose recipients, for example
`--agent codex --agent claude-code`. Omission preserves recipients already
recorded for the skill or source, then uses declaration defaults, initially
Codex and Claude Code. List, remove, and doctor default to all recipients.
Install and update use recorded recipients and modes without overrides.

## Discover and Add

```sh
skill list <source> --json
skill list <source> --path skills --full-depth
skill add <source> <name> [another-name]
skill add <source> --all --agent codex --scope user
skill add <source> <name> --branch main --mode copy
skill add /path/to/local/skills <name> --mode edit
```

A source can be a local path, Git URL or shorthand, well-known HTTP source,
or declared source alias. With no names, add installs the only discovered skill
or prints choices when there are several. `--all` selects current and future
members on unnamed updates. Names and `--all` cannot be combined.

`link` is the default and links pinned cache content. `copy` installs pinned
copies. Local sources in these modes must be Git repositories; only committed
content is installed. `edit` links a live local directory and accepts no
requirement. `--path` narrows source discovery; `--full-depth` searches recursively.

Choose at most one requirement form:

```sh
skill add <source> --branch main
skill add <source> --revision <commit>
skill add <source> --exact 1.2.3
skill add <source> --from 1.2.3
skill add <source> --up-to-next-minor-from 1.2.3
skill add <source> --from 1.2.3 --to 1.8.0
```

Without a requirement, core selects the latest version tag or the default
branch when no tags exist.

## Maintain Skills

```sh
skill list --json
skill install
skill update
skill update <name> --json
skill update <name> --apply
skill remove <name> --agent codex
skill remove <name> [another-name]
skill init my-skill
skill doctor --json
skill doctor --root /path/to/project-a /path/to/project-b --json
```

- `list` reports managed installations, including missing or drifted ones.
- `install` restores exact locked content and leaves lock bytes unchanged.
  It takes no source, recipient, or mode override.
- `update` previews against disk. Names limit the selection; omission reconciles
  every declared skill and membership of `--all` sources. Use `--apply` when
  the user's task authorizes writing the update. It resolves again and prints
  differences before replacing files. `--json` is for previews only.
- `remove` requires names. An agent filter removes only those recipients;
  removing an `--all` member records an exclusion against reinstallation.
- `init` creates a named directory and `SKILL.md`, or `SKILL.md` in the current
  directory when unnamed. Existing files cause an error.
- `doctor` reports installation and source problems. `--root` audits explicit
  projects and cannot combine with `--scope user`.

Commands never prompt. Add, install, remove, and init perform their named
mutations immediately. Respect the user's requested scope and action.

## Interpret Results

JSON reports have `schemaVersion: 1` and sorted keys. Missing optional values
are omitted. List reports use `kind: installed|source`; update reports contain
`changed` and per-file before/after snapshots; doctor contains `ok` and `roots`.
File snapshots use base64 for bytes and typed directory/symlink entries.

Exit status is `0` for success or doctor warnings, `1` for operation failure or
doctor errors, and `64` for usage errors. Read the one-line stderr remedy on
failure. Recovery notices use stderr and the CLI retries a recovered transaction
once. Read commands may fetch/cache data; interrupted-transaction recovery can
restore files.

See [the CLI reference](https://github.com/skill-cli/cli/blob/master/Documentation/Reference/CLI.md)
for complete report schemas and options.
