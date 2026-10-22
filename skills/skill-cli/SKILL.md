---
name: skill-cli
description: Use the skill CLI to add, list, restore, update, remove, initialize, diagnose agent skills, or watch source changes from declared sources in project or user scope.
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
Watch subscriptions in `agents.json` and baselines in `agents.watch` are shared
with `agents watch`; reports include skills, instruction units, and artifacts.

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

A source can carry the same choices as typed selectors: `@branch:`, `@ref:` or
`@revision:`, `@exact:`, `@from:`, `@minor:` (up to next minor), `@path:`, and
`@skill:` for one skill name. Selectors and options that give the same field
must agree.

```sh
skill add larksuite/cli@from:1.0.0@skill:lark-base
skill add owner/repo@branch:main@path:skills --all
```

## Maintain Skills

```sh
skill list --json
skill install --json
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

## Watch Sources

```sh
skill watch add <source> --branch main --path collection
skill watch
skill watch status --scope user --json
skill watch diff <source> [name] --kind skill --json
skill watch diff <source> [name] --kind instructions
skill watch diff <source> [name] --kind artifact
skill watch seen <source>
skill watch seen <source> --revision <commit>
skill watch remove <source>
```

Use `--scope user` on any watch subcommand for shared user state. Add accepts
aliases, existing source IDs, or locations and the same requirement forms as
skill add. Local sources must be Git repositories. Git subscriptions follow
the declared branch or default branch, regardless of version or revision
requirements; well-known sources follow their index.

Add subscribes without installing content and marks current content seen;
repeating add acknowledges it again. Status (the default) compares with that
baseline. Diff shows full before/after snapshots; optional name and kind filters
narrow its output. Uncommitted source files are ignored. Reports include
instruction units and artifacts because the subscription state is shared.

Seen acknowledges current content or a specified Git revision. Well-known
sources do not accept `--revision`. Remove drops the subscription and baseline,
keeping declarations, locks, and installed content. Diff, seen, and remove accept
a subscribed alias, source ID, or location. Status and diff may fetch content but
do not change state or installations. Scheduling is the caller's responsibility.
Add, seen, and remove mutate immediately and do not accept `--json`.

## Interpret Results

JSON reports have `schemaVersion: 1` and sorted keys. Missing optional values
are omitted. List reports use `kind: installed|source`; update reports contain
`changed`, resolved versions when available, per-agent membership, missing-lock
status, and per-file before/after snapshots; install reports restored skills;
doctor contains `ok`, `roots`, and checks with `kind: skills`.
File snapshots use base64 for bytes, executable flags, and typed directory/symlink
entries. Membership describes managed state independently of target presence;
a missing lock does not grant ownership of an existing target.
Watch status has `sources`; diff has one `source` and includes file snapshots
with executable bits. Baselines contain full Git `revision` IDs or artifact
digests; changes identify `skill`, `instructions`, or `artifact`.

Exit status is `0` for success or doctor warnings, `1` for operation failure or
doctor errors, and `64` for usage errors. Read the one-line stderr remedy on
failure. Read commands may fetch/cache data; doctor inspects existing state
without fetching or writing. Pending recovery is an error check with the affected
state path. Run `skill install --scope user` for user state or `skill install`
in the affected project root. Mutating commands recover pending transactions,
report on stderr, and retry once.

See [the CLI reference](https://github.com/skill-cli/cli/blob/master/Documentation/Reference/CLI.md)
for complete report schemas and options.
