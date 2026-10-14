#!/usr/bin/env bash
# Installs amplitude/swift-create-xcframework at a pinned revision from source.
# Intended for CI only — requires Swift 6.2 or newer.

set -euo pipefail

SWIFT_CREATE_XCFRAMEWORK_VERSION="2e980ae30cad93bc5d417be11d223ee7820c9cdc"
SWIFT_CREATE_XCFRAMEWORK_REPO="https://github.com/amplitude/swift-create-xcframework.git"
INSTALL_PREFIX="${INSTALL_PREFIX:-$HOME/.local}"
CACHE_DIR="${SWIFT_CREATE_XCFRAMEWORK_CACHE_DIR:-$HOME/.cache/swift-create-xcframework}"

export PATH="${INSTALL_PREFIX}/bin:${PATH}"

if command -v swift-create-xcframework &>/dev/null; then
	echo "swift-create-xcframework already on PATH: $(command -v swift-create-xcframework)"
else
	echo "Installing swift-create-xcframework ${SWIFT_CREATE_XCFRAMEWORK_VERSION} into ${INSTALL_PREFIX} ..."

	mkdir -p "$(dirname "${CACHE_DIR}")"
	if [[ ! -d "${CACHE_DIR}/.git" ]]; then
		git clone --no-checkout \
			"${SWIFT_CREATE_XCFRAMEWORK_REPO}" "${CACHE_DIR}"
	fi
	git -C "${CACHE_DIR}" remote set-url origin "${SWIFT_CREATE_XCFRAMEWORK_REPO}"
	git -C "${CACHE_DIR}" fetch --depth 1 origin "${SWIFT_CREATE_XCFRAMEWORK_VERSION}"
	git -C "${CACHE_DIR}" checkout --detach "${SWIFT_CREATE_XCFRAMEWORK_VERSION}"

	make -C "${CACHE_DIR}" install prefix="${INSTALL_PREFIX}"
fi

if ! command -v swift-create-xcframework &>/dev/null; then
	echo "error: swift-create-xcframework not found on PATH after install" >&2
	exit 1
fi

echo "Using: $(command -v swift-create-xcframework)"
