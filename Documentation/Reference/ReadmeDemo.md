# README demo

## Recording the README demo

From a task worktree, build the release executable and run the recorder:

```sh
swift build -c release
python3 Scripts/record-demo.py
```

The recorder uses `.build/readme-demo/` for an isolated HOME, project, and
local Git source. It creates `review` and `commit` skills, installs both,
subscribes to the source, commits a change to `review`, runs `skill watch`,
and applies the update. Git permits only the `file` protocol during recording;
the build may fetch package dependencies. Fixed fixture contents, identity,
and timestamps make the displayed revisions reproducible.

Every displayed command must succeed with empty stderr. The recorder checks
that both installed copies contain the updated content and limits stdout to
25 lines. It writes these files under `Documentation/Assets/Demo/`:

- `record.json`: commands, stdout, and exit codes for the terminal renderer
- `provenance.json`: source and dependency revisions, executable version and
  digest, toolchain, recorder digest, fixture revisions, and normalizations

Commands use `~`, and the CLI normally abbreviates its isolated HOME itself.
Any remaining absolute HOME is replaced with `~` and each affected field and
replacement count is recorded. If replacements occur, the exact private path
mapping remains in `.build/readme-demo/normalizations.json`; retain that
receipt privately when publishing the recording. One final stdout newline is
removed when present, as recorded per command. No other output is edited.
Fixture directories are removed on exit.

## Rendering and checking

`recipe.json` copies the font family and colors from the organization's
[DESIGN.md](https://github.com/skill-cli/.github/blob/master/DESIGN.md) and
records its revision and digest. Review the recipe against that revision
before rendering. Dimensions use the terminal renderer's defaults. The recipe
has no dependency on a local organization checkout.

Set `STEWARD` to the installed `github-repo-steward` skill directory, then run:

```sh
python3 "$STEWARD/scripts/render_terminal.py" \
  --record Documentation/Assets/Demo/record.json \
  --spec Documentation/Assets/Demo/recipe.json \
  --output-dir Documentation/Assets/Demo
python3 "$STEWARD/scripts/render_terminal.py" \
  --record Documentation/Assets/Demo/record.json \
  --spec Documentation/Assets/Demo/recipe.json \
  --output-dir Documentation/Assets/Demo --check
```

Review `Demo-light.svg` and `Demo-dark.svg` in both README themes. Commit the
recording, provenance, recipe, and both SVGs together. Re-record after CLI
output changes; re-render after recording or design-token changes. The
renderer check compares both exports with the committed inputs without
executing the recorded commands.
