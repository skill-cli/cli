# README demo

Edit [script.yml](../../.github/assets/terminal/script.yml) to change the
README session's fixture, commands, or expectations. The generated
[recording](../../.github/assets/terminal/recording.json) and
[light](../../.github/assets/terminal/terminal-light.svg) and
[dark](../../.github/assets/terminal/terminal-dark.svg) SVGs live beside it.

[CI](../../.github/workflows/ci.yml) calls the shared Swift package workflow
configured by [swift-package.json](../../.github/swift-package.json).
Its demo job builds the `skill` release executable and re-records the script
in an isolated environment. Recording drift fails validation and uploads the
regenerated `recording.json`. Download it, review the changed output, and commit
the accepted recording. The required aggregate check is `validate / result`;
source policy is `policy / policy`.

## Local rendering

Render and check both terminal SVGs and the social preview locally with the
`github-readme-design` toolchain against
[skill-cli/.github's DESIGN](https://github.com/skill-cli/.github/blob/master/DESIGN.md),
[fonts](https://github.com/skill-cli/.github/tree/master/.github/design/fonts),
and [catalog](https://github.com/skill-cli/.github/blob/master/profile/catalog.json).
Follow the toolchain's [renderer reference](https://github.com/showxu/skills/blob/master/skills/github-readme-design/references/renderers.md)
for setup, rendering, and check commands. Keep temporary inputs under ignored
`.build/` in a task worktree. The terminal SVGs outline text in Google Sans Code.
Review both appearances and commit the exports with the accepted recording.

## Social preview

The committed [PNG](../../.github/assets/social-preview/social-preview.png) uses
the same organization DESIGN, fonts, and catalog. The catalog's light-page icon
resolves to this checkout's `.github/assets/logo/logo-light.png`.
Use the renderer reference above to render and check the `cli` repository card,
review the result, and commit it.
