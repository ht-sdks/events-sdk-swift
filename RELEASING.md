Releasing
=========

Use `release.sh` to perform releases.  This script will perform all the safety checks as well
as update Version.swift, commit the change, and create tag + release.  History since the last
released version will be used as the changelog for the release.

ex: $ ./release.sh 1.1.1

CI will automatically build and upload XCFramework zip assets on each release. See [xcframework-release.yml](.github/workflows/xcframework-release.yml).