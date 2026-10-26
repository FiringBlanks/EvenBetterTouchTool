# Delivery and validation — 2026-10-25

## Artifacts

- Standalone Apple Silicon application: `build/EvenBetterTouchTool.app`
- Installable archive: `build/EvenBetterTouchTool-2.5.0-arm64.zip`
- Archive checksum: `build/EvenBetterTouchTool-2.5.0-arm64.zip.sha256`
- Raw local build/test log: `build/volume-swap-check.log`
- Double-click installer: `Install.command`
- Local installer: `install.sh` (inspect using `./install.sh --dry-run` first)
- Uninstaller: `uninstall.sh`

The app is ad-hoc signed with stable bundle ID `org.evenbettertouchtool.app`. It is not notarized. The renamed app was installed locally in the current user’s Applications folder using the provided installer. The original same-user daemon was stopped; its configuration and LaunchAgent were backed up. The installed settings window was opened, the new branding was verified, and the driver enumerated the selected trackpad. No permission grant, native gesture preference change, login registration, or custom action was performed; native setup and physical acceptance tests remain outstanding; calibration is optional.

## Verified results

Build host: Apple Silicon, macOS 26.6.2, Swift 6.3.2, Command Line Tools. Target: `arm64-apple-macosx14.0`, Swift 5 language mode, optimized build.

`make check` completed successfully:

- Native application compilation: PASS, no compiler warnings.
- Deterministic automated core suite: **177 core + 29 app-model + 14 shortcut lifecycle + 4 native indicator tests passed, 0 failed (224 total)**.
- `--smoke-test`: PASS (default schema validation and AppKit-linked executable startup).
- `codesign --verify --strict`: PASS.
- App `Info.plist` validation: PASS.
- Individual shell syntax checks of installer, uninstaller, migration, and packaging scripts: PASS.

The test suite covers three/four-finger recognition, directions, 10 mm → 10 tab intervals, fractional accumulation, submillimeter samples, reversal, stationary input, cancellation, count/identity changes, staggered landing/release, taps versus swipes, physical-button tap cancellation, invalid/duplicate/noisy frames, direction locking, jitter, profiles/global fallback, mapping thresholds, safety gates/native pass-through, dedicated media command encoding, volume steps/clamping, application shortcut targeting, sequence planning, atomic config persistence, migration/import backups, schema/range rejection, import consent reset, and independent single-stroke X/Y calibration.

UI checks used `--ui-preview`, which uses a temporary disabled configuration and never starts the contact driver. All eight settings sections were opened. The gesture grid and editor, profile icons/edit controls, calibration interface, native setup instructions, General controls, sensitivity controls, and diagnostics interface were inspected. A volume-step override was changed using the real text field; `3.00` was reflected in the control and persisted as `3` in the isolated JSON. Standard Select All and Quit were verified. The 2.1 settings preview additionally verified outside-click and X dismissal without saving, editor Reset, gesture-only Save while another row edit remained pending, global row Save, row dimming/On-Off indicators, pending sensitivity edits, global Reset, dynamic Enabled/Disabled labels, and Quit discarding an unsaved row edit. The real configuration stayed byte-for-byte unchanged during these isolated checks. No live media, input, system volume, permission, or login action was invoked during these UI checks.

The installer dry run successfully detected the original exact-name same-user daemon at `~/.local/bin/threefinger` and its `com.firedev.threefinger.plist` LaunchAgent. It reported the migration plan without stopping, moving, installing, or replacing anything. A subsequent real installation successfully performed legacy migration and opened EvenBetterTouchTool. Uninstall side effects remain a manual acceptance test.

## Outstanding physical acceptance tests

Follow [MANUAL-TESTS.md](MANUAL-TESTS.md) on the intended M4 MacBook Air. In particular, actual device callback compatibility, distance calibration accuracy, native gesture conflicts, Finder tab accessibility structure, media delivery to Music/Spotify/browsers, hardware audio controls, physical press versus tap timing, permission revocation, sleep/wake/reconnection, actual startup at login, emergency shortcut under real input, and idle CPU have **not** been hardware validated. Automated command-plan tests do not prove those behaviors.

Three-finger click Play/Pause is enabled by default and retains the native click; Notification Center has no built-in opening action. The raw driver and symbolic shortcut preference IDs use private/undocumented interfaces. Unsupported audio devices fail with diagnostics. See [COMPATIBILITY.md](COMPATIBILITY.md) for the full API investigation, safety gates, and alternatives.

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

## Version 2.2.0 checks

The isolated settings preview showed the native EvenBetterTouchTool/Edit/Settings menus. Settings menu navigation opened Trackpad Calibration. The main calibration page showed “Ready to use without calibration,” live contacts, and a collapsed optional Precision calibration section; Adjust Sensitivity opened controls labeled in percentages. Preview uses no driver, so these checks do not establish sensor accuracy or physical action delivery. Automated regression cases verify relative versus measured units, unconfirmed dimensions, no calibration blocker, relative volume/stationary/reversal behavior, tap/swipe separation, measurement-start clicks waiting for lift, Save-only measurement/unit changes, and settings visibility surviving foreground changes. Native OS permission and gesture conflict gates remain active.

The 2.2.0 tested executable was installed with the local installer, and its bytes match the build. The existing JSON configuration remained byte-for-byte unchanged. The installed app’s main menu contains EvenBetterTouchTool, Edit, and Settings; its real-device calibration page shows relative mode with precision calibration collapsed. Both OS permissions currently need approval for this changed ad-hoc build; no grant or custom action was performed during verification.

## Version 2.2.1 checks

The preview’s Global three-finger right editor was changed to Sequence with one shortcut: Continuous was enabled and switched on successfully. Adding a second shortcut disabled it with a visible explanation; removing that shortcut re-enabled it. Clicking Save persisted the single-shortcut Sequence with continuous=true in the isolated preview configuration. The preview starts no gesture driver and sends no keyboard actions. Core tests verify count-based repeats, fractions, reversal, stationary contacts, application targeting, and multi-step single-trigger behavior. An app-model test verifies explicit gesture Save persistence. Actual shortcut delivery and timing remain hardware tests.

## Version 2.3.0 checks

Build, smoke, signature, metadata, and script checks passed. The core suite tests custom/native scroll directions, normal scrolling, synthetic and line-wheel bypass, fresh/stale contacts, staggered release, momentum ending/expiration, and disabled filtering; keyboard plans, symbolic shortcut resolution, and deterministic volume-dismissal deadlines are covered too. App-model tests inspect real Quartz event objects (modifier edges, arrow Fn/NumericPad flags, F11 flags, and preservation of held modifiers) without posting them. These event-object tests need access to the host graphics session: the restricted process stalled inside CGEvent construction and was terminated; the complete final suite passed in the normal session. No test injected input or changed system audio.

The disabled UI preview showed the three system-action buttons, volume preview, and filter status. Clicking Preview Volume Indicator changed its status from Hidden to Visible, then back to Hidden automatically; the preview changes no system volume. The menu-bar controller falls back to the screen's top-right corner if its icon is hidden. System Settings was inspected: native Mission Control is four-finger up, native App Exposé is Off, and keyboard Mission Control/Applications windows/Show Desktop are enabled on Control-Up/Control-Down/F11. This verifies configuration, not physical gesture delivery. Actual browser scroll interception, native system action delivery, and audio-level feedback remain physical acceptance checks after permission approval.

New components: `Sources/Core/ScrollFilter.swift`, `KeyboardPlan.swift`, `SystemShortcutChoice.swift`, and `VolumePresentation.swift`; `Sources/App/VolumeIndicator.swift` owns the nonactivating feedback panel. No private Control Center or native-gesture suppression interface is used.

## Version 2.4.0 checks

The pure press recognizer tests mouse down/up, three/four contacts, wrong count/button, stale frames, late contact arrival, release ordering, drag motion, replaced fingers, cooldown, reset, and tap cancellation. Tap tests cover forgiving holds, staggered release, late fourth-finger landing, drift, independent swipe cancellation, cooldown, per-app/cell overrides, old schemas, validation, and persistence. Existing distance/native-scroll/keyboard/volume tests remain passing.

The isolated disabled preview enabled Click → Play/Pause, opened and edited its complete press options, and explicitly saved the mapping. It then saved a forgiving tap override without enabling that Tap mapping. Both persisted in the preview JSON. No gesture engine ran and no playback event was posted during preview checks. Actual hardware pressing, native click side effects, cross-device correlation, and active media-session behavior remain manual acceptance checks. `Sources/Core/TouchOptions.swift` contains the parameter types and pure press recognizer; the existing listen-only button tap performs runtime correlation.

## Version 2.4.1 defaults and user feedback

The user confirmed 0.05 seconds (not 0.5) as the preferred Chrome left/right swipe cooldown and reported that three-finger physical click Play/Pause works on their Mac. These choices are now the defaults for fresh configurations and restored Chrome profiles; tap playback stays disabled. Finder's horizontal cooldown remains zero. Automated checks verify default/restored Chrome mappings, enabled press playback, disabled tap playback, existing saved preference preservation, and Save-only Restore Defaults behavior. Other gesture, event-encoding, and installer tests remain passing.

The built/downloadable app is 2.4.1. The user's working installed 2.4.0 app is deliberately left running; neither its executable nor its saved configuration was changed, preserving existing OS approvals and working custom values. The current profile already uses 0.05 seconds in both Chrome directions and has click playback enabled. Installing the new binary later may require fresh permission approval because local ad-hoc code identities change. The user's click report is hardware feedback, not a claim that every physical acceptance test passed.

## Version 2.5.0 checks

Build, signature, metadata, smoke, and shell checks passed. Four native AppKit indicator tests inspect the actual panel frame while the status item expands and percentage changes from 9% to 99% to 100%, actual fade closure, revival during an existing fade without a stale close, and idle timeout plus fade. The tests use a normal macOS graphics session, temporary UI, no input injection, and no audio changes. Pure state tests cover fade revival, volume/nonvolume gesture classification, reversed native directions, mapping swaps, inherited profile values, disabled row preservation, missing cells/profiles, and Reset. App-model tests verify that swaps never write/apply before Save and persist only in the selected profile.

The 2.5.0 disabled preview was opened, but computer-use visual inspection was blocked because the Mac was locked. The user was asked to unlock it manually. Grid layout, actual mouse-triggered dismissal, and a physical continuous-volume session remain manual checks; no visual pass is claimed for those. The working installation and saved configuration were not modified during build/testing. See the manual checklist before claiming hardware acceptance.
