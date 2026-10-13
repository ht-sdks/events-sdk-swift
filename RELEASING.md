Releasing
=========

Releases require a version-bump PR followed by a tag and GitHub release from `main`.
The repository requires pull requests for changes to `main`.

Do not use `release.sh` for this flow: it still attempts to push directly to `main`.
Use an authenticated GitHub CLI (`gh auth login`) and start with a clean working tree.

## Prepare the version-bump PR

1. Fetch and update your local `main`, then create a release branch from it.
2. Choose a version greater than the current version and update the
   `__hightouch_version` constant in `Sources/Hightouch/Version.swift`.
3. Commit that file, push the release branch, and open a PR targeting `main`.
4. Wait for CI to pass and merge the PR. Do not create the release tag before merging.

If `release.sh` already created a local version commit but its push was rejected,
create a release branch at that commit, push the branch, and open the PR. Reuse the
existing version bump; do not rerun the script.

## Publish after merging

Set the new version and previous release tag (these values are examples):

```bash
RELEASE_VERSION=1.0.0
PREVIOUS_VERSION=0.2.0
git fetch origin main --tags
```

Confirm the version-bump PR is present on `origin/main`, its version matches
`RELEASE_VERSION`, and CI is passing. Then create the release from that fetched commit:

```bash
gh release create "$RELEASE_VERSION" \
  --target "$(git rev-parse origin/main)" \
  --title "Version $RELEASE_VERSION" \
  --generate-notes \
  --notes-start-tag "$PREVIOUS_VERSION"
```

This creates the tag and GitHub release. Use a plain version tag such as `1.0.0`,
without a `v` prefix.

## Verify release assets

The tag triggers [XCFramework Release](.github/workflows/xcframework-release.yml).
Check that it succeeds and uploads `Hightouch.zip`, `Hightouch.sha256`, `Sovran.zip`,
and `Sovran.sha256` to the release. Do not build these assets locally.

`HightouchBraze` is distributed through SwiftPM under the same tag; it is not
included in the XCFramework assets. If asset upload fails, rerun the workflow or
dispatch it with the existing tag and `dry_run=false`; do not create another release.
