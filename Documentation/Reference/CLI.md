# CLI Reference

The package builds the `skill` executable. Homebrew also installs a
Swift-prefixed `swift-skill` executable that invokes the same CLI.

Portable installed entrypoints:

```bash
skill --help
swift-skill --help
```

Use `swift-skill` directly when you want the Swift-prefixed entrypoint. The
spelling `swift skill` depends on Swift driver external-command dispatch and is
not part of the current `skill-cli` command contract. Apple/Xcode toolchains can
dispatch this form through `xcrun swift skill`. When the active `swift` comes
from a Swiftly-managed toolchain, this dispatch may fail with an unknown or
missing subcommand error. Treat `swift skill` as optional toolchain behavior,
not as the supported CLI entrypoint.

## Command Families

Visible commands:

```bash
skill add <source>
skill install
skill list [source]
skill doctor
skill remove [skills...]
skill update [skills...]
skill status <source> --watch
skill diff <source> --watch
skill review check|seen|done <source> --watch
skill init [name]
```

Compatibility aliases:

- `add`: `a`
- `list`: `ls`
- `remove`: `rm`, `r`
- `update`: `upgrade`, `check`

## Source Requirements

Canonical requirement flags follow SwiftPM-style spelling:

```bash
skill add owner/repo --branch main
skill add owner/repo --revision abc123
skill add owner/repo --exact 1.2.3
skill add owner/repo --from 1.2.0
skill add owner/repo --up-to-next-minor-from 1.2.0
skill add owner/repo --from 1.2.0 --to 2.0.0
```

Typed shorthand is also supported:

```bash
skill add larksuite/cli@branch:main
skill add larksuite/cli@branch:main@path:skills/lark-base
skill add larksuite/cli@from:1.2.0@skill:lark-base
skill add larksuite/cli@revision:abc123@path:skills/lark-base
```

Rules:

- known requirement labels are `branch`, `revision`, `exact`, `from`,
  `minor`, and `ref`
- known selector labels are `path` and `skill`
- at most one requirement label and one selector label are allowed
- explicit requirement flags conflict with a different shorthand requirement
- explicit `--path` or `--skill` conflicts with a different shorthand selector
- legacy `owner/repo#ref@skill` remains accepted for migration, but typed
  shorthand is the preferred Swift-native syntax

## Install Commands

Install project skills from the resolved file:

```bash
skill install
skill install --scope user
```

`skill install` reads the selected resolved file and materializes pinned skills
into the selected scope's canonical installed-skill surface and agent
projections. It defaults to project scope.

Add skills from a local path, GitHub/GitLab shorthand or URL, direct git URL,
or well-known provider:

```bash
skill list <source>
skill add <source> --agent codex --skill my-skill
skill add <local-source> --mode edit --agent codex --skill my-skill
skill add <source> --mode copy --agent codex cursor
skill add <source> --all --agent "*"
skill add <source> --scope user
```

Install defaults are project scope, link mode, Codex agent, and the selected
skill. `--all` means all discovered skills only. Targeting every supported
agent is explicit through `--agent "*"`.

Install modes:

- `link` is the default managed mode. It materializes a canonical installed copy
  and links native-only agent projections to that canonical copy when needed.
- `copy` writes physical copies to the selected install surfaces.
- `edit` is local-development mode. It requires an unpinned local source,
  symlinks the canonical installed entry to the local source skill directory,
  and links agent projections through that canonical entry. It is rejected for
  remote sources, well-known sources, source requirement flags, and watch
  installs.

Supported agents:

- `codex`
- `claude-code`
- `cursor`
- `gemini-cli`
- `opencode`

Project installs write canonical installed skills under `.agents/skills` in the
current project. User-scope default link-mode installs write canonical installed
copies under `$HOME/.agents/skills`. Agents whose configured project skill
directory is `.agents/skills` use the canonical user directory directly;
native-only agents receive projections in their own skill directories. Project
resolved state is recorded in `.agent/skills.resolved`.
User resolved state is recorded at `$XDG_STATE_HOME/skills/skills.resolved` when
`XDG_STATE_HOME` is set, otherwise `$HOME/.agents/skills.resolved`.

Project source checkouts are cached under `.agent/cache`. User source checkouts
are cached under `$XDG_CACHE_HOME/skill-cli` when `XDG_CACHE_HOME` is set,
otherwise `$HOME/Library/Caches/skill-cli` on macOS or `$HOME/.cache/skill-cli`
on other platforms. Source checkout caches are not the installed skill surface.

List managed skills from resolved state, or scan all installed skill
directories:

```bash
skill list --agent codex --json
skill list --scope user
skill list --all --scope user
skill remove my-skill --agent codex
skill remove --all
```

`skill list` reads the relevant `skills.resolved` file and reports whether each
managed installation still exists on disk. Status values include `installed`,
`missing`, `broken-link`, `copy-drift`, `source-missing`, `copy-fallback`,
`edit-linked`, and `installed-only`. `skill list --all` scans agent skill
directories and includes unmanaged skills that are not tracked by resolved
state.

Diagnose install state without mutating files:

```bash
skill doctor
skill doctor --scope user --agent codex --json
```

`skill doctor` checks resolved-state readability, managed install health,
broken links, missing local sources, copy drift, fallback copies, and unmanaged
installed-only skills.

Update from resolved state:

```bash
skill update my-skill
skill update my-skill --apply
```

## Managed Watch Commands

Preferred managed source commands:

```bash
skill add <source> --watch-only --skill my-skill
skill add <source> --watch --skill my-skill
skill list --watch
skill status <source> --watch --history --json
skill diff <source> --watch --path skills/foo
skill review check <source> --watch --path skills/foo
skill review seen <source> --watch --path skills/foo --note "seen"
skill review done <source> --watch --path skills/foo --note "reviewed"
skill update <source> --from-watch --path skills/foo --apply
skill remove <source> --watch --path skills/foo
```

Managed semantics:

- `add --watch-only` writes `.agent/skills-state.json` only.
- `add --watch` upserts the watch ledger and installs through the watched
  baseline or reviewed commit, not unreviewed `current_head`.
- re-running `add --watch` for the same source and requirement merges paths,
  refreshes `current_head`, and preserves review cursors.
- changing the requirement requires `--replace-requirement`, which resets the
  affected review baseline and cursors and records a ledger event.
- `update --from-watch` installs reviewed or baseline content from a watch; it
  does not advance review cursors.
- `diff --watch` and `review ... --watch` are path-scoped.
- watch status, diff, and review commands refresh the managed source state
  internally before reading or writing watch cursors.
- install lock and watch ledger remain separate stores that share source pin
  and requirement primitives.

Cursor rules:

- `diff` is read-only.
- `check` records checked handoff evidence.
- `seen` advances `last_seen` without review coverage.
- `done` records external review closeout and advances path-scoped review
  coverage.
- `done --all` applies only to watched paths with checked evidence.
