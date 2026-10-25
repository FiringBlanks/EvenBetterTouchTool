# Delivery and validation — 2026-10-25

## Artifacts

- Standalone Apple Silicon application: `build/EvenBetterTouchTool.app`
- Installable archive: `build/EvenBetterTouchTool-2.0.0-arm64.zip`
- Archive checksum: `build/EvenBetterTouchTool-2.0.0-arm64.zip.sha256`
- Raw local build/test log: `build/check.log`
- Double-click installer: `Install.command`
- Local installer: `install.sh` (inspect using `./install.sh --dry-run` first)
- Uninstaller: `uninstall.sh`

The app is ad-hoc signed with stable bundle ID `org.evenbettertouchtool.app`. It is not notarized. The renamed app was installed locally in the current user’s Applications folder using the provided installer. The original same-user daemon was stopped; its configuration and LaunchAgent were backed up. The installed settings window was opened, the new branding was verified, and the driver enumerated the selected trackpad. No permission grant, native gesture preference change, login registration, or custom action was performed; setup/calibration and physical acceptance tests remain outstanding.

## Verified results

Build host: Apple Silicon, macOS 26.6.2, Swift 6.3.2, Command Line Tools. Target: `arm64-apple-macosx14.0`, Swift 5 language mode, optimized build.

`make check` completed successfully:

- Native application compilation: PASS, no compiler warnings.
- Deterministic automated core suite: **80 passed, 0 failed**.
- `--smoke-test`: PASS (default schema validation and AppKit-linked executable startup).
- `codesign --verify --strict`: PASS.
- App `Info.plist` validation: PASS.
- Individual shell syntax checks of installer, uninstaller, migration, and packaging scripts: PASS.

The test suite covers three/four-finger recognition, directions, 10 mm → 10 tab intervals, fractional accumulation, submillimeter samples, reversal, stationary input, cancellation, count/identity changes, staggered landing/release, taps versus swipes, physical-button tap cancellation, invalid/duplicate/noisy frames, direction locking, jitter, profiles/global fallback, mapping thresholds, safety gates/native pass-through, dedicated media command encoding, volume steps/clamping, application shortcut targeting, sequence planning, atomic config persistence, migration/import backups, schema/range rejection, import consent reset, and independent single-stroke X/Y calibration.

UI checks used `--ui-preview`, which uses a temporary disabled configuration and never starts the contact driver. All eight settings sections were opened. The gesture grid and editor, profile icons/edit controls, calibration interface, native setup instructions, General controls, sensitivity controls, and diagnostics interface were inspected. A volume-step override was changed using the real text field; `3.00` was reflected in the control and persisted as `3` in the isolated JSON. Standard Select All and Quit were verified. No live media, input, system volume, permission, or login action was invoked during this UI check.

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
- `Sources/App/ActionExecutor.swift`
- `Sources/App/AppDelegate.swift`
- `Sources/App/AppModel.swift`
- `Sources/App/SettingsViews.swift`
- `Sources/App/TrackpadDriver.swift`
- `Tests/CoreTests.swift`
- `Resources/Info.plist`
- `Resources/AppIcon.icns`
- `scripts/create-icon.swift`
- `scripts/migrate-legacy.sh`
- `scripts/package.sh`
- `Install.command`
- `docs/RELEASE-NOTES.md`
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
