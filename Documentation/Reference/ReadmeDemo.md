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

Use the renderer at the same shared revision as the `presentation` job in
[CI](../../.github/workflows/ci.yml). Set `standard_checkout` to a local
`agents-tools/.github` checkout containing that commit, then extract its
renderer into the ignored build directory:

```sh
standard_checkout=/path/to/agents-tools/.github
standard_revision=$(rg --only-matching --replace '$1' 'presentation.yml@([0-9a-f]{40})' .github/workflows/ci.yml)
mkdir -p .build/presentation-standard
git -C "$standard_checkout" archive "$standard_revision" Scripts/vendor | tar -x -C .build/presentation-standard
python3 -B -E -s .build/presentation-standard/Scripts/vendor/render_terminal.py \
  --record Documentation/Assets/Demo/record.json \
  --spec Documentation/Assets/Demo/recipe.json \
  --output-dir Documentation/Assets/Demo
python3 -B -E -s .build/presentation-standard/Scripts/vendor/render_terminal.py \
  --record Documentation/Assets/Demo/record.json \
  --spec Documentation/Assets/Demo/recipe.json \
  --output-dir Documentation/Assets/Demo --check
```

Review `Demo-light.svg` and `Demo-dark.svg` in both README themes. Commit the
recording, provenance, recipe, and both SVGs together. Re-record after CLI
output changes; re-render after recording or design-token changes. The
renderer check compares both exports with the committed inputs without
executing the recorded commands.
