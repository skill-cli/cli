# Swift-Style Flag Surface

## Status

Accepted

## Design

The canonical flag surface names domain state directly:

- `--scope project|user` for install/list/remove/update scope
- `--mode link|copy` for install mode
- `install` with no source to materialize project skills from
  `.agent/skills.resolved`
- `list <source>` to inspect installable skills from a source
- `list` to inspect managed skills from resolved state and check installed
  presence
- `update --apply` when an update command should mutate state
- `list --all` for installed filesystem inventory, including unmanaged skills
- `--all` for selecting all skills or all watched paths in mutating command
  families
- `--agent "*"` when the caller intentionally targets every supported agent

Do not add `--confirm` for current noninteractive commands. `add` applies by
default; `remove` only mutates explicit skill names or `--all`; `update`
retains preview behavior unless `--apply` is present.

## Rationale

`project` and `user` match the installation locations users reason about.
`link` and `copy` are install modes, not separate boolean toggles. `--apply`
matches the command behavior more precisely than a confirmation flag because it
controls preview-versus-mutation semantics.

`list <source>` is clearer than `add --list` because source inspection is not
an install operation. Default `list` follows the same resolved-state boundary as
`install` and `update`, while `list --all` makes the broader filesystem
inventory explicit. Keeping `--all` out of agent expansion and confirmation
avoids mixing inventory, target selection, and prompt control.

`install` is intentionally not an alias for `add`. `add <source>` mutates the
resolved dependency set, while `install` consumes the project resolved file and
materializes the pinned skill installations.

## Consequences

- Help, docs, smoke tests, and examples prefer the new spelling.
- `add` keeps `a` as its short alias. `install` is a first-class command, and
  install-like compatibility aliases are not part of the `add` surface.
- Internal lock schemas keep using `InstallScope.global` where needed for
  persisted schema compatibility; CLI JSON and terminal output present the
  user-facing name `user`.
