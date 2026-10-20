# README demo

Edit [script.yml](../../.github/assets/terminal/script.yml) to change the
README session's fixture, commands, or expectations. The generated
[recording](../../.github/assets/terminal/recording.json) and
[light](../../.github/assets/terminal/terminal-light.svg) and
[dark](../../.github/assets/terminal/terminal-dark.svg) SVGs live beside it.

[CI](../../.github/workflows/ci.yml) builds the release executable in `smoke`,
then `presentation` re-records the script against that product in an isolated
environment. The pinned organization standard supplies the toolchain,
DESIGN.md, and fonts. CI compares the recording and both SVGs byte for byte
and fails on any difference. The SVGs outline text in Google Sans Code.

When regeneration succeeds but the files differ, CI uploads the regenerated
directory as `presentation-terminal`. Download it, review the recording and
both appearances, and commit its files under `.github/assets/terminal/`.

## Local regeneration

From a task worktree, build `.build/release/skill` with `swift build -c release`,
then follow the toolchain reference's [Local regeneration](https://github.com/showxu/skills/blob/1b72bb9e104586267d0fbdd333df80a26fc81cc0/skills/github-readme-design/references/renderers.md#local-regeneration)
procedure using the package, DESIGN.md, and fonts selected by the standard
pinned in CI. Keep temporary inputs under ignored `.build/`. Run the terminal
check and review both SVGs before committing the script, recording, and exports
together.
