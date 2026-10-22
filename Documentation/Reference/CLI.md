# CLI Reference

`skill` manages declared skills. All resolution, installation, state, and
recovery operations use `AgentsCore` and `AgentsSkills`. Commands match the skills
operations of `agents`; instruction declarations, locked records, and target
files remain untouched.

## Commands

```text
skill add <source> [names…] [--all]
skill list [source] [--json]
skill remove <names…>
skill update [names…] [--apply | --json]
skill init [name]
skill watch
skill watch add <source> [--path <dir>] [requirement options] [--scope project|user]
skill watch status [--json] [--scope project|user]
skill watch diff <source> [name] [--kind skill|instructions|artifact] [--json] [--scope project|user]
skill watch seen <source> [--revision <rev>] [--scope project|user]
skill watch remove <source> [--scope project|user]
skill install [--json]
skill doctor [--root <dir>…] [--json]
```

`skill --help`, `skill watch --help`, and each command's `--help` describe
their options. Running without a subcommand prints help. `skill watch` runs
`watch status` and accepts its options. `skill --version`
prints `skill X.Y.Z` and is available only on the root command; the version
constant lives in `Sources/CLI/EntryPoint.swift`.

Root help includes:

```text
Examples:
  skill add github.com/owner/skills pdf-forms
  skill list
  skill install
  skill update               Preview what re-resolving would change
  skill update --apply       Write the updates and the new lock
```

## Shared Options

| Option | Meaning | Commands |
| --- | --- | --- |
| `--scope project\|user` | Where state lives: project (./.agent) or user (~/.agents). Default: project. | All lifecycle and read commands; `init` uses the current directory |
| `--agent <agent>` | Agent to install for: codex, claude-code, cursor, gemini-cli or opencode. Repeat for several. Default: the agents already recorded for this skill or source, else the declaration's agents, else codex and claude-code. | `add` |
| `--agent <agent>` | Limit to this agent: codex, claude-code, cursor, gemini-cli or opencode. Repeat for several. Default: all recipients. | `list`, `remove`, `doctor` |
| `--path <subdir>` | Search this subdirectory of the source. | `add`, `list <source>`, `watch add` |
| `--full-depth` | Discover recursively beyond conventional skill directories | `add`, `list <source>` |
| `--mode link\|copy\|edit` | How to install: link (default), copy, or edit (a live link to a local source). | `add` |
| `--root <dir>…` | Audit these project directories read-only. Repeat for several. | `doctor` |
| `--json` | Emit a versioned JSON report on stdout | `list`, `install`, `doctor`, update previews, `watch status`, `watch diff` |

Agents are `codex`, `claude-code`, `cursor`, `gemini-cli`, and `opencode`.
Core also accepts `claude` and `gemini` as input aliases. Output uses canonical
IDs. On add, omitted recipients use the agents already recorded for the skill
or source, then declaration defaults (initially Codex and Claude Code).
On installed list, remove, and doctor, omission covers all
recipients. Source listing shows available skills regardless of recipients.
Doctor's agent filter limits installation checks; source checks cover the scope.

Updates use declared paths, recipients, and modes. Installation restores those
recorded in the lock. Neither update nor install accepts a recipient or mode
override. `--path` always refers to source discovery, never a project root;
change directory for project operations or use doctor's `--root` for auditing.
Unsupported options are usage errors.

## Adding and Inspecting Sources

`source` is a local path, Git URL or shorthand accepted by core, well-known
HTTP source, or an existing declaration alias. Add writes the declaration,
installations, and lock together. A skill directory, file, or link that the
scope's lock does not manage is never replaced: add and install stop before any
change and name the path, so move or remove it first.

`<names>`: Skills to add. Omit to add the source's only skill, or to list the
choices when it has several. Explicit names select those skills. `--all` selects
all current and future members on unnamed updates; combining names and `--all`
is a usage error.

`link` links verified, pinned cache content. `copy` installs pinned copies.
Both require a Git repository for local sources and read committed content.
`edit` links live local directories and accepts no requirement.

Requirement options on add map directly to declaration forms:

| Option | Declaration | Matching versions |
| --- | --- | --- |
| `--branch main` | `"branch": "main"` | Git branch |
| `--revision <rev>` | `"revision": "<rev>"` | Git revision |
| `--exact 1.2.3` | `"exact": "1.2.3"` | Exact semantic version |
| `--from 1.2.3` | `"from": "1.2.3"` | At least 1.2.3, below 2.0.0 |
| `--up-to-next-minor-from 1.2.3` | `"upToNextMinor": "1.2.3"` | At least 1.2.3, below 1.3.0 |
| `--from 1.2.3 --to 1.8.0` | `"from": "1.2.3", "to": "1.8.0"` | Half-open range [1.2.3, 1.8.0) |

Choose one requirement form; `--to` requires `--from`. With no requirement,
core uses the latest version tag or the default branch if there are no tags.

A source can end in typed selectors instead of options. A selector starts at
an `@` followed by one of these labels and `:`, so SSH locations such as
`git@host:owner/repo` keep their `@`:

| Selector | Same as |
| --- | --- |
| `@branch:main` | `--branch main` |
| `@ref:v1.2.3` | `--revision v1.2.3`: any branch, tag, or commit |
| `@revision:<rev>` | `--revision <rev>` |
| `@exact:1.2.3` | `--exact 1.2.3` |
| `@from:1.2.3` | `--from 1.2.3` |
| `@minor:1.2.3` | `--up-to-next-minor-from 1.2.3` |
| `@path:<subdir>` | `--path <subdir>` |
| `@skill:<name>` | one skill name after the source |

`skill add larksuite/cli@from:1.0.0@skill:lark-base` is
`skill add larksuite/cli lark-base --from 1.0.0`. Use at most one requirement
selector, one `@path:`, and one `@skill:`; percent-encode an `@` inside a value
as `%40`. A selector and an option that give the same field must agree; both
replace the branch and path of a hosted tree URL. `agents.json` stores the
structured fields, and the alias comes from the location. `watch add` accepts
requirement and path selectors; `@skill:` applies to `add` and `list <source>`.

A source added by location keeps the alias that already declares it, or takes
its last path component. When another source holds that alias, preceding
components are prefixed, as in `anthropics-skills`, then a number is appended.

`list` lists managed lock records, including missing or drifted installs,
one row per recipient. `list <source>` inspects what a source provides.
Source discovery paths can refer to cache materializations and are not stable
identifiers; use the source ID and skill name for identity.

## Watch

`skill watch` shares subscriptions with `agents watch` and reports skills,
instruction units, and well-known artifacts through the same core operations.

`watch add <source>` subscribes without installing content and records the
current baseline as seen. Repeating add acknowledges current content again.
Sources can be declared aliases, source locations, or existing source IDs.
`--path` and requirement options use the same forms as `add`. A local
source must be a Git repository. Git subscriptions follow the declared branch,
or the default branch; version and revision requirements do not select the
watched head. Well-known subscriptions follow the index.

`watch status`, also available as `skill watch`, reports subscriptions in
core's order. Git revisions are abbreviated to seven characters:

```text
local:~/Developer/team-rules  1 commit since 6c09c94 (now 9661957)
  ~ changed  code-review (instructions)   1 file
  ~ changed  pdf   1 file
```

The Git count is commits reachable from the current head but not the seen
revision. A well-known source shows `N artifacts changed` (singular for one),
or `up to date`. Instruction and artifact names carry `(instructions)` or
`(artifact)`; skills have no suffix. Changed items show `1 file` or `N files`;
new and removed items omit the file count. An empty scope prints
`No watched sources.`

`watch diff <source> [name]` prints each changed item's heading and unified
line diffs with three lines of context. Skill paths are relative to the skill
root and prefixed by the skill name, such as `pdf/SKILL.md`. Instruction and
artifact paths are relative to the item.
`--kind skill|instructions|artifact` filters changes and disambiguates shared
names. With no matching changes, diff prints `up to date`.

```text
~ changed  code-review (instructions)  local:~/Developer/team-rules  6c09c94 -> 9661957
--- a/code-review.md
+++ b/code-review.md
@@ -2,7 +2,7 @@
 Review checklist:
 Read the change.
 Check correctness.
-Review the code.
+Review the code and tests.
 Check tests.
 Check edge cases.
 Record findings.
```

Mode changes print `mode pdf/run.sh: 644 -> 755`; unchanged modes are omitted.
Binary content prints `Binary file <path> differs`. Links print
`link <path>: <old> -> <new>` (`none` for an absent link); directories print
`directory <path> added` or `directory <path> removed`.

`watch seen <source>` acknowledges current content. `--revision <rev>` resolves
a Git revision to its full commit ID and can select an older commit. Well-known
sources do not accept `--revision`. `watch remove <source>` removes the
subscription and baseline while preserving declarations, locks, and installed
content. Diff, seen, and remove accept a subscribed alias, source ID, or location.

Mutation confirmations use normalized source IDs:

```text
Watching local:~/Developer/team-rules from 6c09c94.
Marked local:~/Developer/team-rules seen at 9661957.
Stopped watching local:~/Developer/team-rules; installations are unchanged.
```

Well-known confirmations omit revisions: `Watching <source ID>.` and
`Marked <source ID> seen.` Add, seen, and remove do not accept `--json`.
Status and diff emit one JSON object each with `--json`; revisions remain full.
They can fetch upstream content without changing declarations, locks, watch
baselines, installations, or source working trees. Uncommitted source files are
ignored. Scheduling checks is left to the caller.

Watch baselines live in `.agent/agents.watch` for project scope or
`~/.agents/agents.watch` for user scope. `agents.json` owns subscriptions.
A missing subscription suggests `Run 'skill watch' to list subscriptions`;
an invalid revision suggests providing a Git revision that resolves to a commit
in the watched source. Operation failures exit 1; invalid options and unknown
subcommands exit 64, as elsewhere in the CLI.

## Update, Restore, Remove, and Initialize

`update` previews by default, comparing newly resolved declarations
against disk. `update <names…>` limits resolution to named skills;
Unnamed `update` reconciles every declared skill,
including membership changes in `all` selections.

Human update item lines use `+ new`, `~ changed`, `= repinned`, and `- removed`.
Repinned means only the pin moved: content, executable flags, and managed
membership are identical. Items sort in that order, then by name. Revisions use
seven characters; a resolved version displays as `1.2.0 (abc1234)`. Without a
version, the revision is shown alone; an absent side of an addition or removal
shows `none`. When both sides have neither a version nor a revision, as with
live edit links, the entire pin suffix is omitted. Item summaries omit hashes.
Managed membership determines whether a pinless skill is new or removed, even
when there is no physical file difference.

For example, `skill update` can report a pin change without a content diff:

```text
= repinned  pdf  local:~/Developer/team-rules  6c09c94 -> 9661957
  = unchanged  codex (link)  .agents/skills/pdf
Preview only. Run again with --apply to write these changes.
```

Human diffs are for reading. JSON reports carry exact content bytes in base64.
Tabs print verbatim; other control characters in payload lines and upstream
text use visible escapes such as `\r`, `\x1b`, `\x00`, or `\u{202e}`.

File comparisons use unified line diffs with three lines of context and
`--- a/<path>`, `+++ b/<path>`, and `@@` hunk headers. New files use
`--- /dev/null`; removed files use `+++ /dev/null`. Missing trailing newlines
are marked with `\ No newline at end of file`. Empty file creation or removal
prints only `empty file <path> added` or `empty file <path> removed`. Binary, mode,
link, and directory changes use the same rendering as watch diffs. Skill updates
include executable-only changes even when the revision and content hash are
unchanged. Mode labels `644` and `755` represent the absence or presence of any
execute bit, not a complete POSIX permission mask. Content hashes exclude modes.

Skill content differences appear once per skill, using paths relative to its
root prefixed by its name. Identical changes across installations are combined.
Recipient-specific differences, such as divergent local copies, are labeled by
recipient. Installation links moving between cached snapshots are omitted.
Links to live edit targets and changes between link, copy, and edit modes remain
visible, as do symbolic links within the skill content.

```text
~ changed  pdf  local:~/Developer/team-rules  6c09c94 -> 9661957
  = unchanged  codex (link)  .agents/skills/pdf
--- a/pdf/SKILL.md
+++ b/pdf/SKILL.md
@@ -6,7 +6,7 @@
 PDF checklist:
 Open the document.
 Inspect page sizes.
-Inspect PDF pages.
+Inspect PDF pages and metadata.
 Check metadata.
 Check annotations.
 Review extracted text.
Preview only. Run again with --apply to write these changes.
```

Each changed skill includes one membership row per previous or prospective
agent. Rows show `+ added`, `- removed`, or `= unchanged` with the managed
installation mode and physical target path. A mode change shows `~ changed`
and the old and new modes. These labels describe membership, not content: an
unchanged recipient can still receive updated files. Shared paths retain a row
for each agent while file diffs appear once.

```text
~ changed  pdf  local:~/Developer/team-rules
  = unchanged  claude-code (edit)  .claude/skills/pdf
  - removed  codex (edit)  .agents/skills/pdf
  + added  cursor (edit)  .agents/skills/pdf
Preview only. Run again with --apply to write these changes.
```

When `agents.resolved` is missing, the preview begins with
`Lock missing: earlier membership is unknown.` Membership additions do
not imply that target files were absent. Applying still rejects existing
content that the scope does not manage, including an already-correct live link.
A recorded but missing target retains its before membership.

`--apply` prints the preview before core writes. After success, completion lines
use `Removed`, `Added`, and `Updated` for removed, new, and retained recipients
of changed skills, respectively, with agents in alphabetical order. `Updated`
includes the old and new pins when either side has a version or revision, using
the same pin format as the preview. With no pins it prints
`Updated <skill> for <agents>.` Additions and removals print
`Added <skill> for <agents>.` and `Removed <skill> for <agents>.`

```text
~ changed  pdf  local:~/Developer/team-rules  1.2.0 (abc1234) -> 1.3.0 (def5678)
  = unchanged  codex (copy)  .agents/skills/pdf
mode pdf/run.sh: 644 -> 755
Updated pdf for codex: 1.2.0 (abc1234) -> 1.3.0 (def5678).
```

Completions appear only after the skill operation succeeds. Named and all-skill
updates print `No skill changes.` when unchanged, including with `--apply`.
A preview can become stale; `--apply` resolves again and
displays the content it will actually write. `--json --apply` is a usage error.

Completion lines name their content and destinations. For example,
`skill add <source> pdf`, `skill update pdf --apply`, and `skill remove pdf`
print:

```text
Installed pdf for claude-code, codex (link).
Updated pdf for claude-code, codex: 6c09c94 -> 9661957.
Removed pdf for claude-code, codex.
```

`install` restores exact locked pins, hashes, modes, and recipients. It does not
resolve newer versions and takes no source argument. Unavailable pins or content
that fails digest verification cause failure.

`remove` requires names and removes their declarations, files, and lock entries.
With `--agent`, it removes only those recipients. Removing a member of an `all`
selection records an exclusion so an update does not reinstall it.

`init [name]` creates a skill directory and `SKILL.md` in the current directory;
without a name it creates `SKILL.md` directly there. Existing files are errors.

## Doctor and State

Doctor reports core's skill checks, including missing installations, drift,
broken links, newer matching source revisions, and uncommitted source content.
`--root` accepts multiple directories, either after one option or repeated.
Each root is an explicit project directory; `--root` cannot combine with user
scope. A nonexistent root is an error. Without roots, project scope uses the
current directory and user scope uses HOME.

| Scope | Declaration | Lock | Cache |
| --- | --- | --- | --- |
| Project | `.agent/agents.json` | `.agent/agents.resolved` | `.agent/cache/` |
| User | `~/.agents/agents.json` | `~/.agents/agents.resolved` | `~/.agents/cache/` |

Project roots are the current directory, not a search up the Git ancestry.
Core resolves installation locations, including `CODEX_HOME`,
`CLAUDE_CONFIG_DIR`, and `XDG_CONFIG_HOME` when applicable. User state remains
under HOME's `.agents` directory.

Read commands and previews do not recover interrupted transactions or write
declarations, locks, or installations. Doctor inspects existing state without
fetching sources, writing caches, or creating locks. A pending transaction is
reported as skill check `pending-recovery`. It is an error check: the state is
inconsistent until recovery, so doctor sets `ok` to false and exits 1. Human
output includes the affected state directory. To finish recovery, run
`skill install --scope user` for `~/.agents`, or run `skill install` in the
project root for that project's `.agent` directory.

Commands that change a scope finish pending recovery before proceeding. When
core reports recovery, the CLI prints a notice on stderr and retries that
operation once. A second recovery or any other failure stops the command.

## Output and Exit Status

Human-readable stdout is the default. Commands are non-interactive and never
prompt; add, remove, init, and install perform their named actions immediately.
Only `update --apply` writes an update. Diagnostics and recovery notices go to
stderr. Human paths are project-relative inside the project in project scope,
`~/…` under HOME, and absolute otherwise. Local source IDs abbreviate HOME,
for example `local:~/Developer/team-rules`. Installed skill listings use the
same path rules. JSON retains full revisions, hashes, and absolute paths.

Errors preserve line breaks. The first line starts with `Error: `; every
continuation line is indented by two spaces, including Git stderr and remote
text that itself begins with `Error:`. Trailing blank lines are dropped.
Punctuation is added only when the error's last non-empty line lacks it.
The capitalized remedy is its own final sentence on a separate line, indented
by two spaces. Tabs print verbatim; all other controls within each line,
including ESC, CR, C1, and bidi controls, use visible escapes:

```text
Error: Unknown command 'unknown'.
  Run 'skill --help' for usage.
```

A directory without a Git repository produces a Git failure and exits 1:

```console
$ mkdir -p "$HOME/not-a-repository"
$ skill add "$HOME/not-a-repository" --all
Error: Git could not clone ~/not-a-repository.
  fatal: repository '~/not-a-repository' does not exist.
  Check Git access and the source location.
```

Human-readable source text preserves tabs and visibly escapes other control
characters.

| Code | Meaning |
| --- | --- |
| `0` | Success, including help/version, unchanged previews, and doctor warnings |
| `1` | Operation failure or a completed doctor report containing an error check |
| `64` | Invalid usage, including unknown commands, options, or invalid option combinations |

Unknown commands and subcommands report `Unknown command '<name>'` and exit
64 even when `--help` or `-h` comes before or after the unknown name.
Command-path validation stops at `--`; leaf command positionals remain arguments.

Doctor's `ok` means there are no error checks; warnings do not make it false.
A failed operation emits no successful JSON report. JSON stdout contains only
one object and a trailing newline; recovery notices remain on stderr.

## JSON Schemas

All reports have integer `schemaVersion: 1`. Object keys are sorted. Arrays
follow core's deterministic ordering; doctor roots retain input order.
Optional properties are omitted when unavailable, never encoded as `null`.
Filesystem paths, including update file paths, are absolute. Watch item `oldPath`
and `newPath` are relative to the source search root (`--path` when present);
watch diff file `path` is item-relative. File bytes use standard base64. Missing
`before` or `after` means that entry is absent, distinct from an empty file or
directory.
Clients should ignore unknown properties; incompatible changes require a new
schema version. Diagnostic IDs are core-defined strings, not a closed enum.

| Command | Schema | Required root fields |
| --- | --- | --- |
| `list --json` | [Installed list](Schemas/installed-list.schema.json) | `schemaVersion`, `kind: "installed"`, `scope`, `skills` |
| `list <source> --json` | [Source list](Schemas/source-list.schema.json) | `schemaVersion`, `kind: "source"`, `scope`, `source`, `skills` |
| `update --json` | [Update](Schemas/update.schema.json) | `schemaVersion`, `scope`, `changed`, `skills` |
| `watch status --json`, `watch --json` | [Watch status](Schemas/watch-status.schema.json) | `schemaVersion`, `scope`, `sources` |
| `watch diff --json` | [Watch diff](Schemas/watch-diff.schema.json) | `schemaVersion`, `scope`, `source` |
| `install --json` | [Install](Schemas/install.schema.json) | `schemaVersion`, `scope`, `skills` |
| `doctor --json` | [Doctor](Schemas/doctor.schema.json) | `schemaVersion`, `ok`, `roots` |

An empty installed list:

```json
{"schemaVersion":1,"kind":"installed","scope":"project","skills":[]}
```

An empty update preview:

```json
{"schemaVersion":1,"scope":"project","changed":false,"skills":[]}
```

A healthy doctor report:

```json
{"schemaVersion":1,"ok":true,"roots":[{"root":"/project","scope":"project","ok":true,"checks":[]}]}
```

Doctor checks include `kind: "skills"` alongside their IDs, severity, message,
and optional path. `pending-recovery` is an error; other severities come from core.
`install --json` reports restored skill rows with `name`, `agent`, `mode`, and
absolute `path`. These definitions are CLI-owned and do not expose core's
encoded lock objects.

Update skill rows include optional `oldVersion` and `newVersion` from the resolved
version tags. Absent sides, live edit installations, well-known artifacts, and
Git resolutions without a selected version tag omit those properties. Full
`oldRevision`/`newRevision` and `oldHash`/`newHash` retain their existing meaning.
Regular file snapshots add boolean `executable` alongside `kind` and `base64`.

Each skill row also includes `lockMissing` and `membership`. Membership rows have
`agent`, absolute physical `path`, `before`, and `after`. Each side is either
`{ "kind": "absent" }` or `{ "kind": "installed", "mode": "link|copy|edit" }`.
Rows cover the union of recorded and prospective recipients, sorted by canonical
agent ID, including unchanged results. Agents sharing a path keep separate
membership rows while physical file changes remain deduplicated. Membership is
managed state, independent of physical presence: a missing target can still have
installed before membership. `lockMissing: true` means before membership is
unrecorded; it does not establish ownership of an existing target. These fields
are additive within schema version 1; older reports can omit them.

Watch `sources` entries (and the single diff `source` object) include `alias`,
normalized `source`, `seen`, `current`, optional Git `commitCount`, and `changes`.
Each baseline is either `{ "revision": "<full commit ID>" }` or
`{ "artifacts": { "<name>": "sha256:…" } }`. Changes include `name`,
`kind: "skill" | "instructions" | "artifact"`,
`change: "new" | "changed" | "removed"`, `fileCount`, and available
`oldPath`, `newPath`, `oldDigest`, and `newDigest`. Diff adds `files` with
`path` and optional `before`/`after` snapshots; regular files include
`kind: "file"`, `base64`, and boolean `executable`. Directory and symlink
entries use the same shapes as update previews. Status omits file snapshots.
Artifact digests may change with zero file differences; `fileCount` remains zero.
