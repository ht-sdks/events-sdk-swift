#!/usr/bin/env bash
# Builds Hightouch and Sovran XCFramework zip assets. CI-only — do not run locally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="${SOURCE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

ARTIFACTS=(
	Hightouch.zip
	Hightouch.sha256
	Sovran.zip
	Sovran.sha256
)

# shellcheck source=scripts/install-swift-create-xcframework.sh
source "${SCRIPT_DIR}/install-swift-create-xcframework.sh"

cd "${SOURCE_ROOT}"

echo "Removing stale build state and old artifacts ..."
rm -rf .build
rm -f "${ARTIFACTS[@]}"

echo "Building XCFrameworks ..."
swift create-xcframework \
	--clean \
	--platform ios \
	--platform macos \
	--platform maccatalyst \
	--platform tvos \
	--platform watchos \
	--stack-evolution \
	--zip \
	Hightouch \
	Sovran

echo "Verifying artifacts ..."
for artifact in "${ARTIFACTS[@]}"; do
	if [[ ! -s "${artifact}" ]]; then
		echo "error: missing or empty artifact: ${artifact}" >&2
		exit 1
	fi
done

echo "Done. Produced: ${ARTIFACTS[*]}"
