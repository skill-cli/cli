# Agent Instructions and Declared State

## Status

Draft

## Problem

Agents load two kinds of guidance from disk. Skills are loaded on demand from
skill directories. Instructions are loaded into every session from files such
as `AGENTS.md`, `CLAUDE.md` and `GEMINI.md`, at user level and per project.

`skill` manages skills from pinned sources, but instruction files are copied by
hand. The same sections end up in many repositories and global files, each copy
drifts on its own, and nothing records where a section came from or which
version it is. Nobody can tell which copy is current, and nobody can audit the
files systematically. ChatGPT cannot read local instruction files at all, so
its project and task instructions are pasted from yet another copy.

The skill side has related gaps:

- Intent lives only in command history. A source added with `--all` does not
  follow later additions or removals (#4).
- `install` re-resolves requirements instead of restoring the locked revision
  (#7) and cannot restore well-known sources (#8).
- One mutable checkout per source makes results depend on what ran before
  (#16) and lets inspection commands move it (#9).
- Source identities collide across hosts and between local directories with
  the same name (#14). Two sources can overwrite the same installed skill name
  (#15).
- Watch state is tied to the current directory (#10) and grows a full checkout
  per reviewed commit (#17).

## Goals

- Manage instructions with the same sources, declaration, lock and commands as
  skills: one model with two kinds.
- Make every managed instruction section traceable to a source and a locked
  version, keep repository- or user-specific content editable, and make drift
  detectable.
- Render instructions as a prompt for ChatGPT.
- Restore exactly what the lock records, and re-resolve only on `update`.
- Turn watch into a subscription that reports what changed upstream.

## Non-goals

- Agent runtime configuration such as MCP servers, hooks, subagents and
  settings. These are evaluated separately after instructions ship.
- Collaboration. The tool is the only writer of managed sections; a change to a
  managed section from anywhere else is drift.
- Version control. The tool writes files; each project decides whether and when
  to commit them.
- Compatibility with earlier state files and source syntax. Existing state is
  converted once outside the tool.

## Concepts

| Term | Meaning |
| --- | --- |
| Source | A local directory, Git repository or well-known URL that provides skills, instructions or both |
| Skill | A directory with a `SKILL.md`, loaded by agents on demand |
| Instructions | One Markdown file in a source, loaded by agents in every session |
| Target | A file that agents read instructions from, or the ChatGPT prompt |
| Managed block | The part of a target that the tool writes from sources |
| Custom content | Everything in a target outside the managed block; it belongs to the target's owner |
| Declaration | What the user wants: sources, selected skills and instructions, targets |
| Lock | What was resolved and written: revisions, digests, content hashes |

## Sources

A source can provide both kinds. Discovery is by convention and needs no
manifest.

- Skills: directories containing `SKILL.md` under `skills/` or `.agents/skills/`,
  as today.
- Instructions: `.md` files directly under `instructions/` or
  `.agents/instructions/`. The file name without `.md` is the instructions name.
- `--path <subdir>` moves the search root for both kinds and is recorded in the
  declaration.

An instructions file starts with exactly one level-1 heading and uses level 2
or deeper for everything else:

```markdown
# Canonical Artifacts

Treat conversation, review feedback, and intermediate attempts as editing
context. ...
```

The tool writes the file's content verbatim apart from heading levels (see
[Writing targets](#writing-targets)).

Source IDs are normalized: Git sources include the host and path
(`github.com/owner/repo`), local sources use their absolute path
(`local:/path/to/dir`), and well-known sources use their URL host and path.
Different repositories never share an ID.

## Scopes and Files

| Scope | Declaration | Lock | Targets |
| --- | --- | --- | --- |
| Project | `.agent/skills.json` | `.agent/skills.resolved` | Project skills; `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` at the project root |
| User | `~/.agents/skills.json` | `~/.agents/skills.resolved` | User skills; each agent's user instructions file; the ChatGPT prompt |

Both files are local state and are not committed. The lock lives with its
project, so moving a repository moves its state. Watch state follows the same
scope rules.

### Declaration

The command line edits the declaration; editing it by hand is possible.

```json
{
  "agents": ["codex", "claude-code"],
  "sources": {
    "rules": { "path": "~/Developer/rules", "branch": "main" },
    "swift-skills": { "url": "github.com/swift-library/skills", "from": "1.0.0" }
  },
  "skills": {
    "swift-skills": { "select": "all", "agents": ["codex", "claude-code"] }
  },
  "instructions": {
    "AGENTS.md": {
      "agents": ["codex", "cursor", "opencode"],
      "sections": ["rules:canonical-artifacts", "rules:first-principles-work"]
    }
  },
  "watch": ["github.com/anthropics/skills"]
}
```

- `agents` is the default target list. Without it the default is `codex` and
  `claude-code`.
- `select` is `"all"` or a list of names. `"all"` follows the source's current
  membership on `update`.
- Instruction targets list sections in order as `source:name`.
- The `chatgpt` target may name a local custom-content file appended by
  `render`.

### Lock

```json
{
  "version": 1,
  "sources": {
    "github.com/swift-library/skills": {
      "kind": "git",
      "url": "https://github.com/swift-library/skills.git",
      "requirement": { "from": "1.0.0" },
      "revision": "16548e957446d2b33a6792f180d6c3f815e76722",
      "version": "1.4.0"
    },
    "local:/Users/me/Developer/rules": {
      "kind": "local",
      "requirement": { "branch": "main" },
      "revision": "a03a475f0c1d2e3b4a5968778695a4b3c2d1e0f9"
    }
  },
  "skills": {
    "swiftui-patterns": {
      "source": "github.com/swift-library/skills",
      "path": "skills/swiftui-patterns",
      "hash": "sha256:…",
      "installs": { "codex": { "mode": "link" }, "claude-code": { "mode": "link" } }
    }
  },
  "instructions": {
    "AGENTS.md": {
      "agents": ["codex", "cursor", "opencode"],
      "headingOffset": 1,
      "blockHash": "sha256:…",
      "sections": [
        {
          "name": "canonical-artifacts",
          "source": "local:/Users/me/Developer/rules",
          "path": "instructions/canonical-artifacts.md",
          "hash": "sha256:…"
        }
      ]
    }
  }
}
```

- Every map is keyed by identity, so duplicates cannot exist. A skill name is
  unique within a scope: adding a skill whose name is already installed from
  another source fails until the existing one is removed.
- `revision` (Git and local Git sources) and `digest` (well-known sources) are
  the locked state. `install` uses them and nothing else.
- Install paths and target paths are derived from scope, agent and file name;
  the lock does not store them.
- Output is sorted and has no timestamps. Writes take a file lock and replace
  the file atomically.

## Commands

The kind is selected by what is read from a source:

| Form | Meaning |
| --- | --- |
| `--skill [names…]` | Read skills; with names, only those |
| `--instructions [names…]` | Read instructions; with names, only those |
| both | Read both kinds |
| neither | Read both; proceed when the source has exactly one item, otherwise list the items and ask for a selection |
| `--all` | Every item of the selected kinds |

`--agent <agent>` chooses targets for both kinds and defaults to the
declaration's `agents`.

| Command | Behavior |
| --- | --- |
| `add <source>` | Update the declaration, resolve, write, update the lock |
| `update` | Show what re-resolving the declaration would change. `--apply` writes files and the lock. Shows a diff for drifted managed blocks before replacing them |
| `install` | Restore skills and managed blocks from the lock without resolving. A missing revision or digest is an error, never a substitution |
| `list [source]` | Installed skills and managed instructions per target; with a source, the skills and instructions it provides |
| `remove` | Remove skills, or sections with `--instructions <name>`, from the declaration, files and lock |
| `doctor` | Compare lock and disk: missing installs, drifted skill copies, drifted managed blocks, outdated sources, duplicate sections across scopes, files over an agent's size limit |
| `render <target>` | Print the assembled prompt for `chatgpt` |
| `watch …` | Subscription; see [Watch](#watch) |

`update` without `--apply`, `list`, `doctor`, `render` and `watch` without a
subcommand that records state do not change files, the lock, the watch state or
which revision a cached checkout points to. They may fetch new objects into a
source mirror.

## Agents and Instruction Files

| Agent | User scope | Project scope |
| --- | --- | --- |
| `codex` | `$CODEX_HOME/AGENTS.md` | `AGENTS.md` |
| `claude-code` | `$CLAUDE_CONFIG_DIR/CLAUDE.md` or `~/.claude/CLAUDE.md` | `CLAUDE.md` |
| `cursor` | Not file-based | `AGENTS.md` |
| `opencode` | `$XDG_CONFIG_HOME/opencode/AGENTS.md` or `~/.config/opencode/AGENTS.md` | `AGENTS.md` |
| `gemini-cli` | `~/.gemini/GEMINI.md` | `GEMINI.md` |
| `chatgpt` | Rendered prompt, no file | Rendered prompt, no file |

Agents that read the same file share one target. Declaring different sections
for agents that share a file is an error.

## Writing Targets

A file target consists of custom content and at most one managed block:

```markdown
# Example Agent Guide

<!-- BEGIN managed by skill: do not edit this block. Edit its sources and run `skill update`. -->
## Canonical Artifacts

...

## First-Principles Work

...
<!-- END managed by skill -->

## Task Route

...
```

1. Sections appear in declared order.
2. The managed block is one contiguous region. On first write it goes where the
   first matching existing section was, otherwise below the file's level-1
   title, otherwise at the start. Custom content keeps its bytes and order.
3. The BEGIN and END comments delimit the block. Their text is fixed and carries
   no versions. Sections inside the block are identified by heading.
4. An existing section outside a block whose heading matches a declared section
   is adopted silently when its content is identical. Otherwise `update` shows
   the difference and replaces it only with `--apply`.
5. Two sources providing the same heading for one target is an error.
6. A section installed at both user and project scope produces a `doctor`
   warning.
7. Source headings are level 1. When the target has a level-1 title, every
   heading in the block is shifted one level down. A shift beyond level 6 is an
   error.
8. Sections are separated by one blank line; the file ends with one newline.
9. Removing the last section removes the block and its comments. A file the
   tool created and that has no custom content left is deleted.
10. `doctor` warns when a file exceeds the reading agent's limit, such as
    Codex's default 32 KiB.
11. Any change inside the block that does not match `blockHash` is drift.
    `doctor` reports it and `update` restores the source version after showing
    the difference.
12. Unpaired or nested markers are an error; nothing is written.

`render chatgpt` prints the selected sections in order followed by the target's
custom-content file, without markers.

A lost lock is recoverable: the block's comments and section headings, matched
against the declared sources, rebuild the `instructions` entry.

## Watch

Watch is a subscription to upstream sources.

```text
$ skill watch
github.com/anthropics/skills  3 commits since a1b2c3d (now 9f8e7d6)
  + new      pdf-forms
  ~ changed  frontend-design   4 files
  - removed  legacy-docx
local:/Users/me/Developer/rules  up to date
```

| Command | Behavior |
| --- | --- |
| `watch add <source>` | Subscribe, without installing anything |
| `watch` | Report each subscribed source since its last seen revision, per skill and instructions: new, changed, removed |
| `watch diff <source> [name]` | Show the changes |
| `watch seen <source>` | Advance the source's seen revision |
| `watch remove <source>` | Unsubscribe |

Installing and updating use `add` and `update`. Scheduling periodic checks is
left to the caller.

## Source Cache

Each source has one mirror in the scope's cache. Resolution reads requirements
against the mirror. Materialization extracts the exact locked revision into a
directory named by source and revision, shared by every consumer of that
revision and pruned when no lock references it. No command moves a working tree
that another operation depends on.

## Removed Behavior

- The review workflow of watch: `review check`, `review seen`, `review done`,
  their status, outcome, open-item and granularity fields, packet export, and
  installing from a watch baseline.
- The `--watch`, `--watch-only`, `--from-watch` and `--replace-requirement`
  flags; watch is a command family.
- Decoding of earlier lock and ledger formats, and the `owner/repo#ref@skill`
  shorthand.
- Built-in source aliases.
- `user` replaces `global` in all state and code.

## Open Questions

- Product and command name. The command stays `skill` until instructions ship;
  renaming is decided afterwards.
- Runtime configuration (MCP servers, hooks, subagents, settings) as further
  kinds.
- Skill inventory, reference graph and directional-reference checks for skill
  collections.

## Related Issues

#4, #7, #8, #9, #10, #14, #15, #16, #17, #18, #22
