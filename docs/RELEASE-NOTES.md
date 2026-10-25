# EvenBetterTouchTool 2.1.1 — permission setup and readiness

- The Enabled master switch keeps a blue track when the app window is inactive. Its accessibility representation remains a normal switch.
- Dashboard now distinguishes the master selection, the contact stream, and actual custom-gesture readiness. It lists missing permissions, native gesture confirmations, calibration, device, and other blockers. Ready mappings stays at zero while required permissions are unverified.
- Permission controls provide targeted Set Up requests, exact app-path copying, Show App in Finder, Recheck Permissions, and a relaunch helper. Inline instructions explain how to select the app from an empty Input Monitoring list and how to repair an apparently enabled but stale Accessibility entry.
- Relaunch refuses pending edits rather than autosaving or discarding them. All existing explicit Save/Reset behavior is preserved.
- Added a step-by-step permissions and readiness guide. No permission, native preference, calibration value, or setup confirmation is changed automatically.

Requires Apple Silicon and macOS 14+. Extract `EvenBetterTouchTool-2.1.1-arm64.zip` and run Install.command or install.sh. After installing this local ad-hoc build, re-add the current installed app to privacy permissions if an old enabled entry is not recognized; then relaunch. Complete native conflict setup and measured trackpad calibration, and click Save.

Validation: 107 core tests and 15 app-model tests pass (122 total), along with compilation, signature, metadata, and script checks. Hardware gesture/media/audio/lifecycle acceptance testing remains outstanding. This remains an experimental, ad-hoc signed, unnotarized release using private MultitouchSupport APIs; physical multi-finger click remapping remains disabled.
