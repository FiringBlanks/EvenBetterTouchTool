#!/bin/bash
# Preserve user settings and migration backups. Never restart the old daemon.
set -euo pipefail
target="${1:-$HOME/Applications/EvenBetterTouchTool.app}"
if [[ ! -d "$target" ]]; then echo "App not found: $target. Pass its exact path if installed elsewhere." >&2; exit 1; fi
identifier=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null || true)
[[ "$identifier" == "org.evenbettertouchtool.app" ]] || { echo "Refusing to remove an unrelated app" >&2; exit 1; }
echo "First turn OFF General → Start at Login in EvenBetterTouchTool."
"$target/Contents/MacOS/EvenBetterTouchTool" --quit-running
for attempt in {1..20}; do
    remaining=$(/bin/ps -U "$(id -u)" -o pid=,comm= | /usr/bin/awk '$NF ~ /\/EvenBetterTouchTool.app\/Contents\/MacOS\/EvenBetterTouchTool$/ {print $1}')
    [[ -n "$remaining" ]] || break
    sleep 0.1
done
[[ -z "${remaining:-}" ]] || { echo "App is still running. Quit from its menu, then retry." >&2; exit 1; }
# Remove this app's registered login item even if the GUI is already closed.
"$target/Contents/MacOS/EvenBetterTouchTool" --unregister-login
rm -rf "$target"
echo "Removed $target. Settings and backups remain in ~/.config."
echo "Remove stale Accessibility/Input Monitoring entries in System Settings if desired. Restore native gestures manually."
