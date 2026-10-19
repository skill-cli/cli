# Upgrading from 0.2

skill 0.3 rebuilt the CLI on agents core. It does not read 0.2 state and never
replaces an installation its own lock does not manage, so an upgrade moves the
0.2 installations aside and declares their sources again.

## What Changes

| 0.2 | 0.3 |
| --- | --- |
| `skills.resolved` in `.agent/`, `~/.agents/`, or `$XDG_STATE_HOME/skills/` | `agents.json` declaration and `agents.resolved` lock in `.agent/` or `~/.agents/` |
| Watch ledger `.agent/skills-state.json` | `watch` subscriptions in `agents.json`, baselines in `agents.watch` |
| Installations recorded with scope `global` and mode `symlink` | User scope and `link` mode |
| Default recipient Codex | Default recipients Codex and Claude Code |

Installation directories do not change: Codex, Cursor, Gemini CLI, and
OpenCode share `~/.agents/skills` in user scope, and Claude Code uses
`~/.claude/skills`. 0.2 files stay in place and are never read or modified.

## Commands

| 0.2 | 0.3 |
| --- | --- |
| `skill add <source> --skill a b` | `skill add <source> a b` |
| `skill add <source> --watch-only` | `skill watch add <source>` |
| `skill status <source> --watch`, `skill review check` | `skill watch` |
| `skill diff <source> --watch` | `skill watch diff <source>` |
| `skill review seen`, `skill review done` | `skill watch seen <source>` |
| `skill update <source> --from-watch` | `skill update <names>`, then `--apply` |
| `owner/repo#ref@skill` | `owner/repo@ref:<ref>@skill:<skill>` (0.3.1 and later) |
| `--agent "*"` | One `--agent` per recipient |
| `a`, `ls`, `rm`, `upgrade`, `check` | `add`, `list`, `remove`, `update` |

Review cursors, outcomes, open items, and review packets have no 0.3
equivalent. Watch reports what changed since the seen baseline; keep review
judgments with the process that makes them.

## Steps

1. Record each 0.2 source from `skills.resolved`: its location, its skills, and
   for each installation the agent, mode, path, and any requirement.
2. Keep a copy of `skills.resolved` and of the 0.2 executable until the upgrade
   is verified.
3. Move each recorded installation out of its skill directory into a sibling
   directory at the same depth, such as `~/.agents/skills.0.2/`, so relative
   links still resolve if you move them back. Leave entries that 0.2 did not
   record in place.
4. Upgrade, for example with `brew upgrade skill-cli`.
5. Add each source again with its recorded names, recipients, mode, and
   requirement:

   ```sh
   skill add <location> <names…> --scope user --mode <mode> --agent <agent>
   ```

   Edit-mode sources take no requirement. A source without a requirement
   resolves its latest version tag, which can be newer than the 0.2 pin.
6. Subscribe watched sources again with `skill watch add <source>`.
7. Check the result with `skill list --scope user` and
   `skill doctor --scope user`.
8. After verification, delete the moved entries, the 0.2 state file, and the
   0.2 source cache (`~/Library/Caches/skill-cli` on macOS).

skill 0.3.0 rejects a second source whose location ends in the same component,
such as two `…/skills` repositories. On 0.3.0, declare such sources in
`agents.json` under distinct aliases before adding them; 0.3.1 and later derive
a distinct alias automatically.
