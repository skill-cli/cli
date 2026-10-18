# skill-cli

`skill` manages agent skills from declared sources. Add skills once, restore
exact locked content with `install`, and preview upstream changes before
applying an update. It supports Codex, Claude Code, Cursor, Gemini CLI, and
OpenCode through [agents-tools/core](https://github.com/agents-tools/core).

This is the skills edition of [agents](https://github.com/agents-tools/cli).
`skill add|list|remove|update|init` matches `agents skills` commands;
`skill install|update|doctor` runs the shared skill operations. Instruction
selections, locked instruction records, and target files remain untouched.
`skill watch` matches `agents watch` and shares its subscription state,
including reports of instruction units and well-known artifacts.

## Install

Install the latest stable release from the Homebrew tap:

```sh
brew install skill-cli/tap/skill-cli
skill --help
```

For a development build of `master`, use:

```sh
brew install --HEAD skill-cli/tap/skill-cli
```

The tap provides `skill` and `swift-skill`. Use either executable directly;
`swift skill` depends on the active Swift driver's external-command dispatch.
See the [tap documentation](https://github.com/skill-cli/homebrew-tap#readme)
for packaging and channel details. This checkout documents the 0.3 command
surface; the stable tap may still distribute 0.2 until 0.3 is released.

## Usage

```sh
skill add https://github.com/anthropics/skills.git --all --agent codex
skill list
skill list --scope user --json
skill watch add https://github.com/anthropics/skills.git
skill watch
skill watch diff https://github.com/anthropics/skills.git
skill watch seen https://github.com/anthropics/skills.git
skill install
skill update
skill update pdf --apply
skill remove pdf
skill init my-skill
skill doctor --root /path/to/project-a /path/to/project-b --json
```

Project scope uses the current directory and stores `agents.json`,
`agents.resolved`, `agents.watch`, and `cache/` under `.agent/`. `--scope user`
uses `~/.agents/`. Keep state and caches out of version control.

`add` installs in `link` mode for the recipients already recorded for that skill
or source, otherwise for the declaration's default agents (initially Codex and
Claude Code). Repeat `--agent` to choose recipients. `link` and `copy` install
committed, pinned content from Git sources; `edit` links a live local directory.
An unnamed add installs the only discovered skill or prints choices when there
are several. `--all` follows future membership changes on update.

`watch` subscribes without installing content, reports changes since the last
`watch seen`, and previews file differences. `watch remove` keeps installed
skills and instructions. Scheduling checks is left to the caller.

Commands are non-interactive. Updates preview by default; `--apply` prints the
differences before writing. See the
[CLI reference](Documentation/Reference/CLI.md) for options, JSON schemas,
errors, and exit codes.

## Upgrading from 0.2

0.3 uses the shared `agents.json` declaration and `agents.resolved` lock in
project `.agent/` or user `~/.agents/`. It does not read 0.2 state files.
Add sources again with `skill add`; skill names are positional arguments.
0.2 watch ledgers and the `review` commands are gone: watch is now a
subscription. Subscribe again with `skill watch add` and acknowledge changes
with `skill watch seen`.

## Bundled Companion Skill

Install the companion that teaches agents this command surface:

```sh
skill add skill-cli/cli --branch master --path skills/skill-cli --scope user --agent codex
```

For live local development:

```sh
skill add . --path skills/skill-cli --scope user --agent codex --mode edit
```

## Development

Requires macOS 13 or later and Swift 6.3 or later.

```sh
swift build
swift run skill --help
```

The package consumes core's `master` branch during development. Release
preparation changes this to a published version range. The build-time version
is `BuildInfo.version` in `Sources/CLI/EntryPoint.swift`.

See [Contributing](CONTRIBUTING.md) for the full validation loop,
[Architecture](Documentation/Architecture/Package.md) for ownership,
and [Releasing skill](Documentation/Reference/Release.md) for release checks.
