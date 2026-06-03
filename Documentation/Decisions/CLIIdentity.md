# CLI Identity

## Status

Accepted

## Design

The public command is a singular tool entrypoint for agent skill operations.
Repository and package naming can describe the Swift implementation, but the
installed command should read as the product.

- Primary executable product: `skill`
- Root command name: `skill`
- No `skills` root-command alias
- Homebrew installs `skill`
- Homebrew also installs `swift-skill` as a Swift-prefixed executable name
- `add` keeps the short alias `a`
- `install` is a first-class no-argument command that installs project skills
  from `.agent/skills.resolved`
- `swift skill` is not part of the CLI contract. Apple/Xcode toolchains can
  dispatch `swift <name>` to a `swift-<name>` executable. When the active
  `swift` comes from a Swiftly-managed toolchain, this dispatch may fail with an
  unknown or missing subcommand error. That difference is Swift driver behavior,
  not a `skill-cli` command-surface guarantee.

## Rationale

`skill` names the product surface directly. `skill-cli` remains the package and
distribution identity, while `swift-skill` is a secondary executable name for
users who prefer a Swift-prefixed command.

Keeping `swift-skill` does not require pretending that `swift skill` is portable
across current toolchains. Xcode users may be able to run `xcrun swift skill`,
but the portable Swift-prefixed command remains `swift-skill`. If Swift driver
behavior changes in the future, that can make `swift skill` work in more
environments without changing the `skill-cli` root command.

Root-command naming is separate from subcommand compatibility. The command has
one executable name, while `add` and `install` keep separate dependency
mutation and dependency materialization semantics.

## Related Documentation

- Current structure: `../Architecture/Package.md`
- Command reference: `../Reference/CLI.md`
