#!/bin/bash
# Sourced by local/source and packaged installers. Paths are always passed as arguments.
find_launcher_tool() {
    local project_root="$1"
    if [[ -x "$project_root/scripts/launcher-tool" ]]; then
        printf '%s\n' "$project_root/scripts/launcher-tool"
    else
        if [[ ! -x "$project_root/build/launcher-tool" ]]; then
            make -C "$project_root" build/launcher-tool >&2 || return 1
        fi
        printf '%s\n' "$project_root/build/launcher-tool"
    fi
}
register_installed_app() {
    local registry=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    if [[ -x "$registry" ]]; then "$registry" -f "$1" 2>/dev/null || true; fi
}
create_launch_shortcut() {
    local helper="$1" installed_app="$2" location
    if location=$("$helper" create "$installed_app" /Applications/EvenBetterTouchTool.app "$HOME/Desktop/EvenBetterTouchTool.app"); then
        printf 'Launch from: %s\n' "$location"
    else
        echo 'The app was installed, but a launch shortcut could not be created. Existing files were preserved.' >&2
    fi
    register_installed_app "$installed_app"
}
remove_launch_shortcuts() {
    "$1" remove "$2" /Applications/EvenBetterTouchTool.app "$HOME/Desktop/EvenBetterTouchTool.app"
}
