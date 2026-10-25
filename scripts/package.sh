#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
package="$root/build/EvenBetterTouchTool-2.0.0-arm64"
mkdir -p "$package/scripts" "$package/docs"
ditto build/EvenBetterTouchTool.app "$package/EvenBetterTouchTool.app"
cp Install.command install.sh uninstall.sh README.md LICENSE "$package/"
cp scripts/migrate-legacy.sh "$package/scripts/"
cp docs/MANUAL-TESTS.md docs/COMPATIBILITY.md docs/VALIDATION.md docs/RELEASE-NOTES.md "$package/docs/"
ditto -c -k --sequesterRsrc --keepParent "$package" "$root/build/EvenBetterTouchTool-2.0.0-arm64.zip"
(cd "$root/build" && shasum -a 256 EvenBetterTouchTool-2.0.0-arm64.zip > EvenBetterTouchTool-2.0.0-arm64.zip.sha256)
echo "Package: $root/build/EvenBetterTouchTool-2.0.0-arm64.zip"
