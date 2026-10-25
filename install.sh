#!/bin/bash
# Install the locally built app. No upstream --reinstall, curl, or downloads.
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
source "$root/scripts/launcher-support.sh"
destination="$HOME/Applications"
dry_run=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --destination) [[ $# -ge 2 ]] || exit 2; destination="$2"; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        *) echo "Usage: $0 [--destination /Applications] [--dry-run]" >&2; exit 2 ;;
    esac
done
case "$destination" in /*) ;; *) echo "Destination must be an absolute directory" >&2; exit 2 ;; esac
app="$root/build/EvenBetterTouchTool.app"
if [[ -d "$root/EvenBetterTouchTool.app" ]]; then app="$root/EvenBetterTouchTool.app"; fi
[[ -x "$app/Contents/MacOS/EvenBetterTouchTool" ]] || make -C "$root" all
codesign --verify --strict "$app"
identifier=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")
[[ "$identifier" == "org.evenbettertouchtool.app" ]] || { echo "Unexpected bundle identifier" >&2; exit 1; }
target="$destination/EvenBetterTouchTool.app"
for other in /Applications/EvenBetterTouchTool.app "$HOME/Applications/EvenBetterTouchTool.app"; do
    if [[ -d "$other" && "$other" != "$target" ]]; then
        echo "Another app exists at $other. Re-run with --destination \"$(dirname "$other")\" to update that copy, or remove it first." >&2
        exit 1
    fi
done
if [[ -e "$target" ]]; then
    existing=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null || true)
    [[ "$existing" == "$identifier" ]] || { echo "Refusing to replace an unrelated app: $target" >&2; exit 1; }
fi
if [[ "$dry_run" == 1 ]]; then
    "$root/scripts/migrate-legacy.sh" --dry-run
    printf 'Would install %s at %s; replace an existing app only after saving a backup.\n' "$app" "$target"
    echo "Would add an Applications shortcut, or a desktop shortcut if the main Applications folder is unavailable."
    exit 0
fi
helper=$(find_launcher_tool "$root")
mkdir -p "$destination"
staging=$(mktemp -d "$destination/.evenbettertouchtool-install.XXXXXX")
trap 'rm -rf "$staging"' EXIT
/usr/bin/ditto "$app" "$staging/EvenBetterTouchTool.app"
codesign --verify --strict "$staging/EvenBetterTouchTool.app"
# Stage and validate the entire replacement before stopping any existing daemon.
"$root/scripts/migrate-legacy.sh" --apply
# Quit the old process; pending edits are never saved implicitly.
"$app/Contents/MacOS/EvenBetterTouchTool" --quit-running
for attempt in {1..20}; do
    remaining=$(/bin/ps -U "$(id -u)" -o pid=,comm= | /usr/bin/awk '$NF ~ /\/EvenBetterTouchTool.app\/Contents\/MacOS\/EvenBetterTouchTool$/ {print $1}')
    [[ -n "$remaining" ]] || break
    sleep 0.1
done
[[ -z "${remaining:-}" ]] || { echo "Existing app has not quit. Quit it from its menu and retry." >&2; exit 1; }
if [[ -e "$target" ]]; then
    backup="$HOME/.config/threefinger-migration/app-$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$backup"; /usr/bin/ditto "$target" "$backup/EvenBetterTouchTool.app"; rm -rf "$target"
fi
mv "$staging/EvenBetterTouchTool.app" "$target"
create_launch_shortcut "$helper" "$target"
open "$target"
printf '\nInstalled: %s\n' "$target"
cat <<'MESSAGE'
In the app, complete Setup Assistant and Trackpad Calibration.
Grant EvenBetterTouchTool.app Accessibility and Input Monitoring, then quit/reopen it.
Enable Start at Login in General if desired. The original service is stopped;
its configuration, LaunchAgent backups, and original binary are preserved.
Locally ad-hoc signed rebuilds may need fresh permission grants.
MESSAGE
