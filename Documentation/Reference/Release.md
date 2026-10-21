# Releasing skill

Release in dependency order: **agents-tools/core → the CLIs → their Homebrew
taps**. This checklist owns the `skill` executable release. Core owns its
[release policy](https://github.com/agents-tools/core/blob/master/Documentation/Reference/Release.md);
the [skill tap](https://github.com/skill-cli/homebrew-tap#readme) owns formula
maintenance and publication. Tagging, releases, and tap publication require
maintainer authorization.

Each block is a single command chain that stops at the first failure; tagging
and publishing each refuse to run unless the earlier blocks set their markers.

## Prepare the Candidate

Release timing follows the family [versioning policy](https://github.com/agents-tools/.github/blob/master/VERSIONING.md),
which defers to the governing delivery workflow. Include the version change and
changelog entry in the requirement's final delivery candidate.

1. In a task worktree based on current `origin/master`, select a published core
   version. Replace the development `branch: "master"` dependency with a
   minor-bounded range while core is `0.x`, for example:

   ```swift
   .package(url: "https://github.com/agents-tools/core.git", "0.2.3"..<"0.3.0")
   ```

   Use the actual released version and the next minor version with patch zero.
   Once core is `1.x`, use `from:` to allow compatible updates up to the next
   major. Resolve dependencies and commit `Package.resolved` with the manifest.
2. Choose the CLI version under the family
   [versioning policy](https://github.com/agents-tools/.github/blob/master/VERSIONING.md).
   Update `BuildInfo.version` in `Sources/CLI/EntryPoint.swift`;
   it is compiled into the binary and works in source archives without Git.
   Tests compare output against this constant, not a duplicate version literal.
3. Follow the family [versioning policy](https://github.com/agents-tools/.github/blob/master/VERSIONING.md).
   Move the shipped entries from [Unreleased](../../CHANGELOG.md#unreleased)
   into a versioned section, retaining Unreleased for subsequent work. Prepare
   release notes covering changes, fixes, and upgrade steps, and follow the
   family [change flow](https://github.com/agents-tools/.github/blob/master/MAINTENANCE.md#change-flow).

## Verify the Release Commit

Use a clean task or detached worktree at the exact merged release candidate.
Do not build in the main checkout. Fetch tags, record `release_commit`, and
confirm it equals `origin/master`. Confirm CI passed on this exact commit,
including strict format, release build, tests, and smoke checks.
Let this validation run to completion independently of development CI runs;
development CI is not release validation.

```sh
unset checked_commit checked_version verified_tag &&
  git fetch origin --tags &&
  release_commit=$(git rev-parse HEAD) &&
  master_commit=$(git rev-parse origin/master) &&
  test "$release_commit" = "$master_commit" &&
  worktree_status=$(git status --porcelain) &&
  test -z "$worktree_status" &&
  rm -rf .build/release-validation &&
  swift build -c release --scratch-path .build/release-validation \
    --disable-dependency-cache --manifest-cache none &&
  env -u CODEX_HOME -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME swift test \
    --scratch-path .build/release-validation \
    --disable-dependency-cache --manifest-cache none &&
  xcrun swift-format lint --strict --configuration .swift-format --recursive Package.swift Sources Tests &&
  git diff --check origin/master &&
  .build/release-validation/release/skill --help &&
  checked_commit=$release_commit
```

Lint must produce zero findings. Set the intended version explicitly, using the
CLI's existing `vX.Y.Z` tag convention.

Before using the intended version, run the guard below once with a deliberately
different proposed version. Immediately confirm that
`test "$?" -ne 0 && test -z "${checked_version+x}"` succeeds, then rerun the guard
with the intended version.

```sh
unset checked_version verified_tag &&
  version=X.Y.Z &&
  tag="v$version" &&
  actual=$(.build/release-validation/release/skill --version) &&
  test "$actual" = "skill $version" &&
  existing=$(git tag --list "$tag") &&
  test -z "$existing" &&
  worktree_status=$(git status --porcelain) &&
  test -z "$worktree_status" &&
  head=$(git rev-parse HEAD) &&
  test "$head" = "$release_commit" &&
  checked_version=$version
```

If the commit, manifest, resolution file, or version changes, repeat preflight.
Core uses unprefixed version tags; the CLI's tag convention is independent.

## Publish the CLI

With the configured local signing key available, create a signed annotated tag
on the checked commit. Never move or reuse a published tag.

```sh
unset verified_tag &&
  test "${checked_commit:-}" = "$release_commit" &&
  test "${checked_version:-}" = "$version" &&
  git tag -s "$tag" "$release_commit" -m "Release $version" &&
  git verify-tag "$tag" &&
  tagged_commit=$(git rev-parse "$tag^{commit}") &&
  test "$tagged_commit" = "$release_commit" &&
  verified_tag=$tag
```

Set `notes_file` to the prepared release notes. Push and verify the remote
annotated tag's peeled commit before creating the GitHub release:

```sh
test "${checked_commit:-}" = "$release_commit" &&
  test "${checked_version:-}" = "$version" &&
  test "${verified_tag:-}" = "$tag" &&
  git push origin "refs/tags/$tag" &&
  remote_ref=$(git ls-remote --exit-code origin "refs/tags/$tag^{}") &&
  test "${remote_ref%%[[:space:]]*}" = "$release_commit" &&
  gh release create "$tag" --verify-tag --title "$tag" --notes-file "$notes_file"
```

`--verify-tag` checks existence, so the separate commit comparison is required.
Verify the published version, commit, and notes.

## Validate the Tap Candidate

After both CLI releases are available, update `skill-cli/homebrew-tap` in its
own task worktree. Set the stable archive URL to the `skill` release and compute
SHA-256 from the exact downloaded archive bytes. Keep HEAD as the development
channel. Do not infer the archive digest from Git objects.

Validate the edited formula in a disposable Homebrew environment where the
formula is not already installed. Set `test_tap` to an unused temporary tap
name, then copy the candidate formula from its worktree into that local tap:

```sh
export HOMEBREW_NO_INSTALL_FROM_API=1 &&
  export HOMEBREW_NO_AUTO_UPDATE=1 &&
  tap_checkout=$PWD &&
  formula_name=skill-cli &&
  brew tap "$test_tap" "$tap_checkout" &&
  test_tap_checkout=$(brew --repository "$test_tap") &&
  mkdir -p "$test_tap_checkout/Formula" &&
  cp "Formula/$formula_name.rb" "$test_tap_checkout/Formula/$formula_name.rb" &&
  cmp "Formula/$formula_name.rb" "$test_tap_checkout/Formula/$formula_name.rb" &&
  brew info --json=v2 "$test_tap/$formula_name"
```

Compare the displayed stable URL and SHA-256 with the intended release archive
and its independently computed digest. Keep this candidate unchanged throughout
validation:

```sh
brew fetch --force --build-from-source "$test_tap/$formula_name" &&
  brew install --build-from-source "$test_tap/$formula_name" &&
  brew test "$test_tap/$formula_name" &&
  actual=$(skill --version) &&
  test "$actual" = "skill $version" &&
  actual=$(swift-skill --version) &&
  test "$actual" = "skill $version"
```

Verify both installed `skill --version` and `swift-skill --version` print
`skill $version`. Publish the tap change only after its candidate passes;
remove the disposable environment afterward. Record the release commit, core
pin, archive digest, and formula validation in the release handoff.

After publication, remove `.build/release-validation` and retire the release
worktree after recording the accepted commit, tag, and validation results in
the release.
