#!/bin/bash
# Local migration only. Never downloads a release or changes trackpad preferences.
set -euo pipefail
mode="${1:---dry-run}"
[[ "$mode" == "--apply" || "$mode" == "--dry-run" ]] || { echo "Usage: $0 [--dry-run|--apply]" >&2; exit 2; }
labels=(com.firedev.threefinger homebrew.mxcl.threefinger sh.brew.threefinger)
uid=$(id -u)
backup="$HOME/.config/threefinger-migration/$(date +%Y%m%d-%H%M%S)-$$"
if [[ "$mode" == "--dry-run" ]]; then
    echo "Migration preview: unload the three known legacy user LaunchAgents; archive their plists; stop exact-name legacy processes owned by uid $uid."
    /bin/ps -U "$uid" -o pid=,comm= | /usr/bin/awk '$NF ~ /(^|\/)threefinger$/ {print "Legacy process:", $0}'
    for label in "${labels[@]}"; do
        [[ ! -f "$HOME/Library/LaunchAgents/$label.plist" ]] || echo "Archive: $HOME/Library/LaunchAgents/$label.plist"
    done
    echo "Configuration is preserved. Original binaries and Homebrew formula are not removed."
    exit 0
fi
# Verify process enumeration works before changing any launchd state.
/bin/ps -U "$uid" -o pid=,comm= >/dev/null
mkdir -p "$backup"
if [[ -f "$HOME/.config/threefinger.json" ]]; then cp -p "$HOME/.config/threefinger.json" "$backup/threefinger.json"; fi
for label in "${labels[@]}"; do
    launchctl bootout "gui/$uid/$label" 2>/dev/null || true
    plist="$HOME/Library/LaunchAgents/$label.plist"
    if [[ -f "$plist" ]]; then mv "$plist" "$backup/$label.plist"; fi
done
# ps comm yields the executable path (no arguments). Compare the final component,
# not a broad process-name substring. Never signal another user's process.
while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    kill -TERM "$pid" 2>/dev/null || true
done < <(/bin/ps -U "$uid" -o pid=,comm= | /usr/bin/awk '$NF ~ /(^|\/)threefinger$/ {print $1}')
for attempt in {1..20}; do
    remaining=$(/bin/ps -U "$uid" -o pid=,comm= | /usr/bin/awk '$NF ~ /(^|\/)threefinger$/ {print $1}')
    [[ -n "$remaining" ]] || break
    sleep 0.1
done
if [[ -n "${remaining:-}" ]]; then echo "A legacy process is still running ($remaining). Installation stopped; no force-kill was used." >&2; exit 1; fi
printf 'Legacy migration backup: %s\n' "$backup"
echo "Homebrew remains installed. Do not restart/upgrade its threefinger service alongside the app; uninstall the formula yourself if no longer needed."
