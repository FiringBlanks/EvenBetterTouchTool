# Delivery and validation — 2026-10-25

## Artifacts

- Standalone Apple Silicon application: `build/EvenBetterTouchTool.app`
- Installable archive: `build/EvenBetterTouchTool-2.1.1-arm64.zip`
- Archive checksum: `build/EvenBetterTouchTool-2.1.1-arm64.zip.sha256`
- Raw local build/test log: `build/permissions-check.log`
- Double-click installer: `Install.command`
- Local installer: `install.sh` (inspect using `./install.sh --dry-run` first)
- Uninstaller: `uninstall.sh`

The app is ad-hoc signed with stable bundle ID `org.evenbettertouchtool.app`. It is not notarized. The renamed app was installed locally in the current user’s Applications folder using the provided installer. The original same-user daemon was stopped; its configuration and LaunchAgent were backed up. The installed settings window was opened, the new branding was verified, and the driver enumerated the selected trackpad. No permission grant, native gesture preference change, login registration, or custom action was performed; setup/calibration and physical acceptance tests remain outstanding.

## Verified results

Build host: Apple Silicon, macOS 26.6.2, Swift 6.3.2, Command Line Tools. Target: `arm64-apple-macosx14.0`, Swift 5 language mode, optimized build.

`make check` completed successfully:

- Native application compilation: PASS, no compiler warnings.
- Deterministic automated core suite: **107 core + 15 app-model + 14 shortcut lifecycle tests passed, 0 failed**.
- `--smoke-test`: PASS (default schema validation and AppKit-linked executable startup).
- `codesign --verify --strict`: PASS.
- App `Info.plist` validation: PASS.
- Individual shell syntax checks of installer, uninstaller, migration, and packaging scripts: PASS.

The test suite covers three/four-finger recognition, directions, 10 mm → 10 tab intervals, fractional accumulation, submillimeter samples, reversal, stationary input, cancellation, count/identity changes, staggered landing/release, taps versus swipes, physical-button tap cancellation, invalid/duplicate/noisy frames, direction locking, jitter, profiles/global fallback, mapping thresholds, safety gates/native pass-through, dedicated media command encoding, volume steps/clamping, application shortcut targeting, sequence planning, atomic config persistence, migration/import backups, schema/range rejection, import consent reset, and independent single-stroke X/Y calibration.

UI checks used `--ui-preview`, which uses a temporary disabled configuration and never starts the contact driver. All eight settings sections were opened. The gesture grid and editor, profile icons/edit controls, calibration interface, native setup instructions, General controls, sensitivity controls, and diagnostics interface were inspected. A volume-step override was changed using the real text field; `3.00` was reflected in the control and persisted as `3` in the isolated JSON. Standard Select All and Quit were verified. The 2.1 settings preview additionally verified outside-click and X dismissal without saving, editor Reset, gesture-only Save while another row edit remained pending, global row Save, row dimming/On-Off indicators, pending sensitivity edits, global Reset, dynamic Enabled/Disabled labels, and Quit discarding an unsaved row edit. The real configuration stayed byte-for-byte unchanged during these isolated checks. No live media, input, system volume, permission, or login action was invoked during these UI checks.

The installer dry run successfully detected the original exact-name same-user daemon at `~/.local/bin/threefinger` and its `com.firedev.threefinger.plist` LaunchAgent. It reported the migration plan without stopping, moving, installing, or replacing anything. A subsequent real installation successfully performed legacy migration and opened EvenBetterTouchTool. Uninstall side effects remain a manual acceptance test.

## Outstanding physical acceptance tests

Follow [MANUAL-TESTS.md](MANUAL-TESTS.md) on the intended M4 MacBook Air. In particular, actual device callback compatibility, distance calibration accuracy, native gesture conflicts, Finder tab accessibility structure, media delivery to Music/Spotify/browsers, hardware audio controls, physical press versus tap timing, permission revocation, sleep/wake/reconnection, actual startup at login, emergency shortcut under real input, and idle CPU have **not** been hardware validated. Automated command-plan tests do not prove those behaviors.

Physical multi-finger click remapping is disabled; Notification Center has no built-in opening action. The raw driver and symbolic shortcut preference IDs use private/undocumented interfaces. Unsupported audio devices fail with diagnostics. See [COMPATIBILITY.md](COMPATIBILITY.md) for the full API investigation, safety gates, and alternatives.

## File manifest

Modified or replaced:

- `main.swift`: app entry, version/help, safe local CLI operations, smoke/preview modes.
- `Makefile`: native `.app`, testing, signing, checking, packaging targets.
- `install.sh`: local staged installation and safe legacy migration.
- `uninstall.sh`: identified-app removal and login-item cleanup with settings preservation.
- `README.md`: complete setup/build/install/configuration/troubleshooting/uninstall guide.
- `.gitignore`: build artifacts and Finder metadata.
- `com.firedev.threefinger.plist`: moved out of the active root into `Legacy/`.

New implementation:

- `Sources/Core/CalibrationTrial.swift`
- `Sources/Core/Configuration.swift`
- `Sources/Core/ConfigurationStore.swift`
- `Sources/Core/GestureEngine.swift`
- `Sources/Core/SettingsDraft.swift`
- `Sources/Core/GestureReadiness.swift`
- `Sources/Installer/LauncherManager.swift`
- `Sources/Installer/main.swift`
- `Sources/App/ActionExecutor.swift`
- `Sources/App/AppDelegate.swift`
- `Sources/App/AppModel.swift`
- `Sources/App/SettingsViews.swift`
- `Sources/App/TrackpadDriver.swift`
- `Tests/CoreTests.swift`
- `Tests/AppModelTests.swift`
- `Tests/LauncherTests.swift`
- `Resources/Info.plist`
- `Resources/AppIcon.icns`
- `scripts/create-icon.swift`
- `scripts/migrate-legacy.sh`
- `scripts/package.sh`
- `scripts/launcher-support.sh`
- `Install.command`
- `docs/RELEASE-NOTES.md`
- `docs/PERMISSIONS.md`
- `docs/COMPATIBILITY.md`
- `docs/MANUAL-TESTS.md`
- `docs/VALIDATION.md`

Upstream references preserved, never built or invoked:

- `Legacy/main.swift`
- `Legacy/install.sh`
- `Legacy/uninstall.sh`
- `Legacy/com.firedev.threefinger.plist`
- `Legacy/README.md`

`mt.h` and its upstream ABI attribution are reused unchanged. The MIT `LICENSE` is retained and included in the application and package. Existing demo media remain unchanged.

## 2.1 save-only regression coverage

The app-model tests instantiate the actual model with temporary configuration files, without starting hardware callbacks. They verify that editing and waiting, Quit, Reset, staged imports, restored defaults, row switches, login startup selection, emergency pause, invalid saves, and device discovery never implicitly overwrite saved settings. Explicit Save and scoped gesture Save are tested against real atomic JSON writes. Core tests additionally cover per-app row priority, preservation of individually disabled/unsupported mappings, pending edit conflicts, and new-profile gesture saves.

## 2.1.1 permission/readiness checks

The new readiness tests cover missing Accessibility/Input Monitoring, unsaved setup confirmations, calibration, device selection, row switches, disabled master, emergency pause, legacy daemons, and configuration errors. App-model tests verify ready mappings remain zero until actual permission flags and saved setup/calibration are satisfied. The relaunch guard does not save pending edits.

The isolated preview displayed the blue switch while the privacy settings window was being used, exposed its state as a normal accessibility switch, showed the exact app-path instructions, and successfully relaunched into the same isolated preview mode. macOS Accessibility was inspected read-only and an enabled app entry was present; Input Monitoring showed No Items. No privacy grants were changed, no native settings were changed, and no setup/calibration values were invented. Real gesture execution remains a user acceptance step after those blockers are resolved.

## Installer revision 1 for app 2.1.1

The installer now creates native Finder aliases automatically after app placement, reuses correct aliases on repeat installs, falls back to the desktop if Applications is unavailable, and registers the real app. Uninstall resolves alias arguments and removes only matching shortcuts before deleting the app. A separate Foundation-only helper is included in the package; installing the binary release requires no compiler or Apple Events permission.

Fourteen native filesystem tests pass, including first creation, repeat installs, replacing the app at the same path, conflict/fallback handling, invalid app rejection, direct /Applications installs, symbolic-link cleanup, and the complete create/update/remove shortcut lifecycle. These tests use temporary application fixtures; they do not unregister login items or uninstall the user’s real app. The app source, bundle version, and signing identity are unchanged by this installer-only revision.
