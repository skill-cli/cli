# skill-cli

A native `skill` CLI for installing and watching agent skills.

The implementation is scoped to Codex, Claude Code, Cursor, Gemini CLI, and
OpenCode.

## Requirements

- Swift 6.3 or newer
- macOS 13 or newer

## Build

```bash
swift build
swift test
```

From a source checkout, `swift run` is the development equivalent of the
installed `skill` executable:

```bash
swift run skill --help
swift run skill list
swift run skill list --all
swift run skill add <source> --mode copy
swift run skill install
```

## Install CLI

Install from the Homebrew tap:

```bash
brew install --HEAD skill-cli/tap/skill-cli
skill --help
```

The tap formula installs the main executable as `skill` and also provides the
Swift-prefixed executable `swift-skill`.

Use these installed entrypoints for portable CLI usage:

```bash
skill --help
swift-skill --help
```

`swift-skill` is an executable name, not a separate root command. The spelling
`swift skill` is only a Swift driver convenience when the active toolchain
dispatches external `swift-*` executables. Apple/Xcode toolchains can dispatch
that form through `xcrun swift skill`. When the active `swift` comes from a
Swiftly-managed toolchain, this dispatch may fail with an unknown or missing
subcommand error; use `swift-skill` directly in that case.

## Install Skills

```bash
skill install
skill list <source>
skill add <source> --agent codex --skill my-skill
skill add larksuite/cli@branch:main@skill:lark-base --watch --scope user
skill list --agent codex --json
skill list --all --scope user
skill update my-skill --apply
skill remove my-skill --agent codex
```

`skill install` reads resolved state and materializes pinned skills into the
selected scope's canonical installed-skill surface and agent projections. It
defaults to project scope; pass `--scope user` to restore user-scope installs.
`skill add <source>` adds or changes selected-scope skill dependencies and
updates the resolved file.
`skill list` reports managed skills from the resolved file and checks whether
their installed directories still exist. Use `skill list --all` to scan all
installed skill directories, including unmanaged skills.

Project source checkouts are cached under `.agent/cache`; project installed
skills are materialized under `.agents/skills`. User-scope source checkouts use
`$XDG_CACHE_HOME/skill-cli` when set, otherwise `~/Library/Caches/skill-cli` on
macOS or `~/.cache/skill-cli` on other platforms. User-scope default link-mode
installs materialize canonical installed copies under `~/.agents/skills`. Agents
whose configured project skill directory is `.agents/skills` use the canonical
user directory directly; native-only agents receive projections into their own
skill directories.

Supported source shapes include local paths, GitHub/GitLab URLs and shorthand,
direct git URLs, and well-known skill discovery. Well-known discovery supports
compatibility `files[]` indexes, v0.2 `skill-md`, and digest-verified archive
artifacts.
Source requirements can be expressed with SwiftPM-style flags such as
`--branch`, `--revision`, `--exact`, `--from`, `--up-to-next-minor-from`, and
`--to`, or with typed shorthand such as `owner/repo@branch:main@skill:name`.

## Bundled Companion Skill

This repository includes a `skill-cli` companion skill that teaches agents to
use this CLI for skill lifecycle management. It covers adding, restoring,
listing, updating, removing, watching, and reviewing skills across project and
user scopes.

Install it from the published repository:

```bash
skill add skill-cli/cli@branch:master --path skills/skill-cli --scope user --agent codex
```

From a source checkout, install the local version for development:

```bash
skill add . --path skills/skill-cli --scope user --agent codex
```

## Watch Sources

Managed watch mode records source/path state and gates installs through the
watched baseline or reviewed commit:

```bash
skill add <source> --watch-only --skill my-skill
skill add <source> --watch --skill my-skill
skill diff <source> --watch --path skills/my-skill
skill review check <source> --watch --path skills/my-skill
skill review done <source> --watch --path skills/my-skill --note "reviewed"
skill update <source> --from-watch --path skills/my-skill --apply
```

Watch state lives in `.agent/skills-state.json`. The CLI owns this file; it is
readable and diffable, but not a hand-edited config contract.

## Documentation

- `Documentation/Reference/CLI.md`: command reference
- `Documentation/Decisions/SPMInspiredRegistry.md`: registry design rationale
