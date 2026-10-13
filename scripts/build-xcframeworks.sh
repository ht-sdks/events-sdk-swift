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

cd "${SOURCE_ROOT}"
SOURCE_ROOT="$PWD"
BUILD_ROOT="${SOURCE_ROOT}/.build/xcframework-release"

echo "Removing stale build state and old artifacts ..."
rm -rf "$BUILD_ROOT"
rm -f "${ARTIFACTS[@]}"

python3 "${SCRIPT_DIR}/prepare-xcframework-package.py" "$SOURCE_ROOT" "$BUILD_ROOT/package"

DESTINATIONS=(
	'generic/platform=iOS'
	'generic/platform=iOS Simulator'
	'generic/platform=macOS'
	'generic/platform=macOS,variant=Mac Catalyst'
	'generic/platform=tvOS'
	'generic/platform=tvOS Simulator'
	'generic/platform=watchOS'
	'generic/platform=watchOS Simulator'
)
HIGHTOUCH_FRAMEWORKS=()
SOVRAN_FRAMEWORKS=()
for index in "${!DESTINATIONS[@]}"; do
	archive="$BUILD_ROOT/archives/$index.xcarchive"
	derived="$BUILD_ROOT/derived/$index"
	(
		cd "$BUILD_ROOT/package"
		xcodebuild archive -scheme Hightouch -configuration Release \
			-destination "${DESTINATIONS[$index]}" -archivePath "$archive" \
			-derivedDataPath "$derived" \
			SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
			SWIFT_INSTALL_OBJC_HEADER=YES CODE_SIGNING_ALLOWED=NO
	)
	products="$derived/Build/Intermediates.noindex/ArchiveIntermediates/Hightouch/BuildProductsPath"
	for name in Hightouch Sovran; do
		built=$(find "$archive/Products" "$products" -name "$name.framework" -type d -print -quit)
		framework="$BUILD_ROOT/frameworks/$index/$name.framework"
		test -n "$built"
		ditto "$built" "$framework"
		contents="$framework"
		if [ -d "$framework/Versions/A" ]; then
			contents="$framework/Versions/A"
			for directory in Modules Headers; do
				ln -sfn "Versions/Current/$directory" "$framework/$directory"
			done
		fi
		# SwiftPM archives can omit the Swift modules from the installed framework.
		modules=$(find "$products" -name "$name.swiftmodule" -type d -print -quit)
		test -n "$modules"
		mkdir -p "$contents/Modules" "$contents/Headers"
		ditto "$modules" "$framework/Modules/$name.swiftmodule"
		header=$(find "$derived/Build/Intermediates.noindex/ArchiveIntermediates/Hightouch/IntermediateBuildFilesPath" \
			-path "*/GeneratedModuleMaps*/*" -name "$name-Swift.h" -print -quit)
		if [ -z "$header" ]; then echo "error: missing generated header for $name" >&2; exit 1; fi
		cp "$header" "$framework/Headers/"
		printf 'framework module %s {\n  header "%s-Swift.h"\n  export *\n}\n' "$name" "$name" > "$framework/Modules/module.modulemap"
		if [ "$name" = Hightouch ]; then
			# The privacy manifest must travel with the binary framework, not a build-directory bundle.
			resources="$framework"
			if [ -d "$framework/Versions/A" ]; then resources="$framework/Versions/A/Resources"; fi
			mkdir -p "$resources"
			cp "$SOURCE_ROOT/Sources/Hightouch/Resources/PrivacyInfo.xcprivacy" "$resources/"
			HIGHTOUCH_FRAMEWORKS+=(-framework "$framework")
		else
			SOVRAN_FRAMEWORKS+=(-framework "$framework")
		fi
		find "$framework/Modules/$name.swiftmodule" -name '*.swiftinterface' | grep -q .
		otool -L "$framework/$name"
	done
done

xcodebuild -create-xcframework "${HIGHTOUCH_FRAMEWORKS[@]}" -output "$BUILD_ROOT/Hightouch.xcframework"
xcodebuild -create-xcframework "${SOVRAN_FRAMEWORKS[@]}" -output "$BUILD_ROOT/Sovran.xcframework"
for name in Hightouch Sovran; do
	ditto -c -k --sequesterRsrc --keepParent "$BUILD_ROOT/$name.xcframework" "$SOURCE_ROOT/$name.zip"
	swift package compute-checksum "$SOURCE_ROOT/$name.zip" > "$SOURCE_ROOT/$name.sha256"
done

echo "Verifying artifacts ..."
for artifact in "${ARTIFACTS[@]}"; do
	if [[ ! -s "${artifact}" ]]; then
		echo "error: missing or empty artifact: ${artifact}" >&2
		exit 1
	fi
done

echo "Done. Produced: ${ARTIFACTS[*]}"
