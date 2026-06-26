#!/usr/bin/env bash
# Installs segment-integrations/swift-create-xcframework@2.4.0 from source.
# Intended for CI only — uses the system Swift toolchain, not Mint's bundled SwiftPM.

set -euo pipefail

SWIFT_CREATE_XCFRAMEWORK_VERSION="2.4.0"
SWIFT_CREATE_XCFRAMEWORK_REPO="https://github.com/segment-integrations/swift-create-xcframework.git"
INSTALL_PREFIX="${INSTALL_PREFIX:-$HOME/.local}"
CACHE_DIR="${SWIFT_CREATE_XCFRAMEWORK_CACHE_DIR:-$HOME/.cache/swift-create-xcframework}"

export PATH="${INSTALL_PREFIX}/bin:${PATH}"

if command -v swift-create-xcframework &>/dev/null; then
	echo "swift-create-xcframework already on PATH: $(command -v swift-create-xcframework)"
else
	echo "Installing swift-create-xcframework ${SWIFT_CREATE_XCFRAMEWORK_VERSION} into ${INSTALL_PREFIX} ..."

	mkdir -p "$(dirname "${CACHE_DIR}")"
	if [[ ! -d "${CACHE_DIR}/.git" ]]; then
		git clone --depth 1 --branch "${SWIFT_CREATE_XCFRAMEWORK_VERSION}" \
			"${SWIFT_CREATE_XCFRAMEWORK_REPO}" "${CACHE_DIR}"
	else
		git -C "${CACHE_DIR}" fetch --depth 1 origin "refs/tags/${SWIFT_CREATE_XCFRAMEWORK_VERSION}"
		git -C "${CACHE_DIR}" checkout "${SWIFT_CREATE_XCFRAMEWORK_VERSION}"
	fi

	make -C "${CACHE_DIR}" install prefix="${INSTALL_PREFIX}"
fi

if ! command -v swift-create-xcframework &>/dev/null; then
	echo "error: swift-create-xcframework not found on PATH after install" >&2
	exit 1
fi

echo "Using: $(command -v swift-create-xcframework)"
