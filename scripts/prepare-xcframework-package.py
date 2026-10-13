#!/usr/bin/env python3
"""Stage the tagged core sources and their Sovran dependency for native Xcode archives."""

import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

source, staging = map(Path, sys.argv[1:])
manifest = json.loads(subprocess.check_output(
    ["swift", "package", "--package-path", str(source), "dump-package"]
))
core = next(target for target in manifest["targets"] if target["name"] == "Hightouch")
# Fail if the core's packaging requirements change instead of silently omitting them.
assert len(core["dependencies"]) == 1
assert core["dependencies"][0]["product"][:2] == ["Sovran", "sovran-swift"]
assert not core.get("settings") and not core.get("exclude") and not core.get("sources")
assert core["resources"] == [{"path": "Resources", "rule": {"process": {}}}]
sovran = next(dependency["sourceControl"][0] for dependency in manifest["dependencies"]
              if dependency.get("sourceControl", [{}])[0].get("identity") == "sovran-swift")
url = sovran["location"]["remote"][0]["urlString"]
version_range = sovran["requirement"]["range"][0]
platform_names = {"ios": "iOS", "macos": "macOS", "tvos": "tvOS",
                  "watchos": "watchOS", "maccatalyst": "macCatalyst"}
platforms = ", ".join(f'.{platform_names[p["platformName"]]}({json.dumps(p["version"])})'
                      for p in manifest["platforms"])
staging.mkdir(parents=True)
shutil.copytree(source / core.get("path", "Sources/Hightouch"), staging / "Sources/Hightouch")


def write_manifest(dependency):
    (staging / "Package.swift").write_text(f'''// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Hightouch",
    platforms: [{platforms}],
    products: [.library(name: "Hightouch", type: .dynamic, targets: ["Hightouch"])],
    dependencies: [{dependency}],
    targets: [.target(name: "Hightouch",
                      dependencies: [.product(name: "Sovran", package: "sovran-swift")],
                      resources: [.process("Resources")])]
)
''')


# Resolve only Sovran, using the tagged SDK's requirement, rather than resolving Braze.
write_manifest(f'.package(url: {json.dumps(url)}, '
               f'{json.dumps(version_range["lowerBound"])}..<{json.dumps(version_range["upperBound"])})')
subprocess.run(["swift", "package", "--package-path", str(staging), "resolve"], check=True)
resolved = json.loads((staging / "Package.resolved").read_text())
print("Packaging dependencies:", json.dumps(resolved, indent=2), flush=True)
checkout = next(path for path in (staging / ".build/checkouts").iterdir()
                if path.name.lower() == "sovran-swift")
local_sovran = staging / "sovran-swift"
shutil.copytree(checkout, local_sovran, ignore=shutil.ignore_patterns(".git", ".build"))
package_path = local_sovran / "Package.swift"
text, count = re.subn(r'(\.library\(\s*name:\s*"Sovran",)', r'\1 type: .dynamic,',
                      package_path.read_text())
assert count == 1, "Expected one Sovran library product"
package_path.chmod(package_path.stat().st_mode | 0o200)
package_path.write_text(text)
write_manifest('.package(path: "sovran-swift")')
