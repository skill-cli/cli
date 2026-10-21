# README demo

Edit [script.yml](../../.github/assets/terminal/script.yml) to change the
README session's fixture, commands, or expectations. The generated
[recording](../../.github/assets/terminal/recording.json) and
[light](../../.github/assets/terminal/terminal-light.svg) and
[dark](../../.github/assets/terminal/terminal-dark.svg) SVGs live beside it.

[CI](../../.github/workflows/ci.yml) builds the release executable in `smoke`,
then `presentation` re-records the script against that product in an isolated
environment. The pinned organization standard supplies the toolchain,
DESIGN.md, fonts and catalog. CI compares the recording, both SVGs and the
repository social preview byte for byte and fails on any difference. The SVGs
outline text in Google Sans Code.

When regeneration succeeds but the files differ, CI uploads artifact
`presentation` containing `presentation.tar`, with regenerated `terminal/`
and/or `social-preview/` directories and file modes preserved. Download it,
extract it with `tar -xf presentation.tar -C .github/assets`, review the
recording, both terminal appearances and the preview, and commit the files.

## Local regeneration

From a task worktree, build `.build/release/skill` with `swift build -c release`,
then follow the toolchain reference's [Local regeneration](https://github.com/showxu/skills/blob/9e5d7268232b78f5fbef21ccfb9e3a079f2ef7e3/skills/github-readme-design/references/renderers.md#local-regeneration)
procedure using the package, DESIGN.md, and fonts selected by the standard
pinned in CI. Keep temporary inputs under ignored `.build/`. Run the terminal
check and review both SVGs before committing the script, recording, and exports
together.

## Social preview

The committed [PNG](../../.github/assets/social-preview/social-preview.png) uses
`skill-cli/.github`'s DESIGN, fonts and catalog at the presentation workflow pin
in [CI](../../.github/workflows/ci.yml). The catalog's light-page icon resolves
to this checkout's `.github/assets/logo/logo-light.png`.

Use `standard_dir` for the standard inputs at that exact revision and
`toolchain_dir` for the pinned package prepared by the local regeneration
procedure above, keeping temporary inputs under ignored `.build/`:

```sh
node "$toolchain_dir/src/cli.ts" social-preview render \
  --design "$standard_dir/DESIGN.md" --fonts "$standard_dir/.github/design/fonts" \
  --catalog "$standard_dir/profile/catalog.json" --repository cli \
  --icon .github/assets/logo/logo-light.png \
  --out .github/assets/social-preview/social-preview.png
node "$toolchain_dir/src/cli.ts" social-preview check \
  --design "$standard_dir/DESIGN.md" --fonts "$standard_dir/.github/design/fonts" \
  --catalog "$standard_dir/profile/catalog.json" --repository cli \
  --icon .github/assets/logo/logo-light.png --assets .github/assets/social-preview
```
