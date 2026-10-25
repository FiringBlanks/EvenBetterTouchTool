# EvenBetterTouchTool — macOS trackpad customization

A free, MIT-licensed native SwiftUI menu bar app built from [firedev/threefinger](https://github.com/firedev/threefinger). Customize three- and four-finger gestures with app profiles, calibrated continuous movement, media controls, Core Audio volume, and a graphical setup/diagnostics interface. No subscriptions, dependencies, analytics, or network updater.

**Requires macOS 14+, Apple Silicon, and Xcode Command Line Tools to build.** The raw contact driver uses Apple's private MultitouchSupport framework; future OS compatibility is not guaranteed. Physical multi-finger click remapping is disabled. See [compatibility and API investigation](docs/COMPATIBILITY.md) before enabling custom input.

## Download and change settings

Download the [Apple Silicon release ZIP](https://github.com/FiringBlanks/EvenBetterTouchTool/releases/download/v2.0.0/EvenBetterTouchTool-2.0.0-arm64.zip) from [GitHub Releases](https://github.com/FiringBlanks/EvenBetterTouchTool/releases). Extract it and run `Install.command` (or `./install.sh` in Terminal). The installer places the app in your Applications folder and safely stops the original threefinger service if present. The app is also included directly in the ZIP.

Open **EvenBetterTouchTool** from Applications. Click its **hand icon in the menu bar → Open Settings**. In **Gestures**, choose Global or an app profile, then click a gesture cell to change its action. Use **Applications** for per-app overrides and **Sensitivity** for distance/tap settings. Edits save automatically. Complete Setup Assistant, permissions, and calibration before using custom input.

This initial release is **experimental, locally ad-hoc signed, and not notarized**. Physical trackpad acceptance tests are still pending; see the compatibility and test documents below. macOS may require you to explicitly allow the downloaded app through its normal Privacy & Security controls. The installer does not bypass Gatekeeper or change privacy/gesture preferences.

## Build and install locally

```sh
cd /path/to/EvenBetterTouchTool
make check       # compile, automated tests, signature/plist/script checks
make package     # installable ZIP plus SHA-256 checksum
./install.sh --dry-run
./install.sh
```

The compiled app is `build/EvenBetterTouchTool.app`. Installation defaults to `~/Applications/EvenBetterTouchTool.app`. Use `./install.sh --destination /Applications` if you prefer the system Applications folder and have write access. The package is `build/EvenBetterTouchTool-2.0.0-arm64.zip`; unzip and run the included `Install.command` or `install.sh`. It contains the built app and does not need to download or recompile anything. A `.dmg` is unnecessary: the ZIP includes a complete signed `.app`, installer, uninstaller, and documentation.

The installer stages and verifies the replacement **before** stopping the old utility. It unloads the known original/Homebrew user LaunchAgents, archives their plists and existing config under `~/.config/threefinger-migration/`, then stops only exact-name same-user legacy processes. It preserves old CLI binaries, the Homebrew formula, configuration, and previous app backups. It refuses an unrelated app at the destination or a duplicate copy in the standard Applications locations. It never runs upstream `threefinger --reinstall` or downloads the original release. Root-owned/custom-labeled daemons must be stopped separately if you installed one yourself.

Do not run `brew services start/upgrade threefinger` alongside this app. If you no longer need the original Homebrew formula, uninstall it yourself after migration. The app detects a running original same-user daemon at startup and pauses custom actions; Diagnostics can recheck after migration. It also uses a per-user lock to prevent duplicate app engines.

### First launch

1. Grant **EvenBetterTouchTool.app** Accessibility and Input Monitoring in System Settings → Privacy & Security. Use Dashboard or Setup Assistant to open/request these permissions. Quit/reopen after an Input Monitoring change. The old CLI daemon's grants do not transfer.
2. Complete **Setup Assistant**: turn native Mission Control/App Exposé trackpad swipes OFF, retain four-finger horizontal full-screen switching, restrict page swipes to two fingers or Off, and turn three-finger dragging OFF. Custom taps additionally require Look Up and Tap to click OFF. The full table and reasoning are in [COMPATIBILITY.md](docs/COMPATIBILITY.md). The app does not alter system preferences or suppress native gestures automatically.
3. Verify keyboard shortcuts for Mission Control and Application windows. If the app cannot read a configured shortcut, set a user-verified fallback under General → System Shortcuts. No Control–Arrow shortcut is silently assumed.
4. Open **Trackpad Calibration**. Calibrate X and Y separately using ruler-measured travel, or enter measured active-surface dimensions. Raw normalized/sensor coordinates are not millimeters. No custom gesture runs until the selected device is calibrated and native conflict setup is confirmed.
5. Enable **Start at Login** under General if desired. macOS Login Items manages startup; no second LaunchAgent is installed.

**Emergency disable: Control–Option–Command–Escape.** The menu bar also provides Enable/Disable, Open Settings, Diagnostics, and Quit. If the emergency shortcut cannot register because another application owns it, the app warns you; use the menu bar switch.

## Default mappings

| Gesture | Default action |
| --- | --- |
| Three-finger left/right | Previous/next tab in Chrome and Finder profiles only; 1 mm per step |
| Three-finger up/down | Mission Control / App Exposé, once per contact session |
| Three-finger tap | Dedicated system Play/Pause media command |
| Three-finger physical click | Middle click is the intended action but mapping is **disabled / unsupported** |
| Four-finger left/right | Native desktop gesture; sends no synthetic event |
| Four-finger up/down | Volume up/down, 2 percentage points per 4 mm |
| Four-finger tap | Mute/unmute |
| Four-finger physical click | Unassigned and unsupported |

The defaults describe a fresh configuration. Migration preserves your existing explicit shortcut mappings as global one-shot sequences, including old Chrome/Finder overrides; it backs up the original JSON first. An old normalized threshold cannot be converted to mm without calibration and stays recorded in that backup. Restore an individual cell or app profile to adopt the new defaults.

Continuous gestures retain fractional intervals, reverse without lifting, and stop when movement stops. Distance intervals are adjustable from 0.5–20 mm, globally, per app, or per mapping. Reversing discards the old direction's remaining fraction and starts at the turning point. There is no timed repeat or momentum. Exceptional input bursts are limited and discarded rather than replayed later; see compatibility notes.

## Settings and action library

The native settings window provides Dashboard, a 2×6 gesture grid with cell editors, installed-app profiles/icons, Sensitivity, Trackpad Calibration with live contacts, Setup Assistant, General, and Diagnostics. Native controls support light/dark appearances and accessibility labels. The app lives in the menu bar with no permanent Dock icon by default; General can opt into Dock visibility.

Profiles resolve **enabled application override → global mapping → no action/native pass-through**. A disabled app profile falls back to global; a disabled cell inside an enabled profile explicitly blocks that gesture. Unedited app cells inherit global mappings. Profile sensitivity is independently configurable. Additional applications initially have no tab behavior until you add a profile or global action.

Available actions include tab/desktop navigation, Mission Control, App Exposé, Show Desktop, recent-app switching, browser Back/Forward, system Play/Pause/Next/Previous Track, volume/mute, Lock Screen, screenshot UI, mouse down/up pairs, custom keyboard shortcuts and ordered sequences, opening/activating applications, target-app shortcuts, No Action, and native pass-through. Each action exposes relevant parameters. Notification Center has no reliable public opening API here: assign a custom user-configured system shortcut instead. Click-trigger mappings remain unavailable, but a middle-click **action** may be assigned to another supported gesture. Shortcut sequences and disruptive system actions run once per contact session.

Chrome uses Command–Option–Arrow. Finder uses Control–Tab / Control–Shift–Tab after a focused-window accessibility check for multiple tab controls; no eligible window means no action. Finder's hierarchy needs on-device validation. Media actions use dedicated system media events, **not F8**. Volume uses the current default output device's Core Audio properties and reports unsupported hardware volume/mute gracefully.

### Persistence

Configuration remains at `~/.config/threefinger.json` with `schemaVersion: 2`. GUI changes apply immediately and save using atomic replacement after a brief debounce. Valid external edits reload within two seconds when a GUI save is not pending. Invalid changes are reported; imports validate before applying and save a pre-import backup. Imported local consent/calibration is cleared so a foreign profile cannot silently authorize conflicting native input or a different trackpad scale. Export includes the complete saved configuration. Restore Defaults saves a backup first. Configuration errors are visible, not silently discarded.

Diagnostics displays raw contacts, calibrated movement, recognized gesture, block/cancellation reason, action/result, foreground app, sensitivity, timestamp, and device status. Optional action logging is bounded to 250 in-memory entries; no typed content is logged. Copy Diagnostics puts current diagnostic information on the clipboard only when requested.

## Build, signing, and development

```sh
make all
make test
make check
make package
make SIGN='Apple Development: Your Name (TEAMID)'  # use a consistent signing identity
build/EvenBetterTouchTool.app/Contents/MacOS/EvenBetterTouchTool --version
build/EvenBetterTouchTool.app/Contents/MacOS/EvenBetterTouchTool --smoke-test
open build/EvenBetterTouchTool.app --args --ui-preview    # isolated disabled UI preview
```

The default signature is ad-hoc; the bundle ID is stable: `org.evenbettertouchtool.app`. This is a local build, **not notarized**. A changed ad-hoc binary can invalidate existing privacy grants. Remove/re-add the actual installed app's stale permission entry and relaunch if needed. A consistent proper signing identity improves continuity. Avoid repeatedly granting permissions to changing build-directory copies. Public distribution signing/notarization is a separate release step requiring a developer's own credentials.

The upstream MIT license and `mt.h` attribution are retained. Original daemon source/scripts/plist live in `Legacy/` for reference and are not built or invoked. Components:

- `Sources/Core/CalibrationTrial.swift`: validated single-stroke, separate-axis calibration.
- `Sources/Core/Configuration.swift`: schema, defaults, profiles, validation, safety gates.
- `Sources/Core/ConfigurationStore.swift`: atomic persistence, import, backed-up legacy migration.
- `Sources/Core/GestureEngine.swift`: pure recognition and reusable command planning.
- `Sources/App/TrackpadDriver.swift`: runtime contact bridge, device selection, serial processing, button observation, lifecycle.
- `Sources/App/ActionExecutor.swift`: keyboard/media/mouse events, Finder checks, Core Audio, configured system shortcuts.
- `Sources/App/AppModel.swift`: live settings, permissions, profiles, calibration, diagnostics.
- `Sources/App/AppDelegate.swift`: app singleton, menu bar, window, emergency hotkey.
- `Sources/App/SettingsViews.swift`: native graphical interface.
- `Tests/CoreTests.swift`: deterministic recognition/configuration/command tests.
- `Resources/`, `scripts/`, `Makefile`, `main.swift`: app metadata/icon, local packaging/migration, build and entry point.

Add new actions through `ActionKind`, `ActionPlanner`, the executor, and parameter controls; recognition does not depend on their system implementation. The callback copies only a bounded contact frame, processes on a serial queue, and publishes UI state at a limited rate. A single selected device prevents duplicate engines and cross-device mixing.

## Validation and troubleshooting

See [build/validation results and the file manifest](docs/VALIDATION.md). Run `make check` for automated results and [the manual acceptance checklist](docs/MANUAL-TESTS.md) for hardware testing. Tests exercise synthetic three/four-finger frames, directions, continuous distance, fractions/reversal, stationary input, taps/physical-button cancellation, invalid frames, profiles, action plans/media encodings/volume clamping, persistence/migration, and conflict gates. These are **not proof of hardware gesture accuracy or media delivery**.

- No actions: inspect Dashboard for permission, calibration, setup, selected-device, and legacy-daemon state. Lift all fingers after any app/settings change. Use Diagnostics for the exact block reason.
- No contacts: check Input Monitoring for the installed app, quit/reopen, then Reconnect Trackpad. A broken private ABI fails safely and may require a driver update.
- Double native actions: complete the conflict table; the app cannot suppress native gestures that remain enabled. Do not run the old daemon alongside the app.
- Finder does nothing: use multiple tabs in the focused Finder window. If the OS exposes a different accessibility hierarchy, the guard deliberately does nothing.
- Mission Control/desktops do nothing: enable/check the corresponding system shortcut or confirm an exact fallback in General. Native pass-through only works while the matching native gesture is enabled.
- Media does nothing: establish a macOS-recognized media session; compare with the dedicated keyboard media key. Confirm Accessibility and inspect the diagnostic action result.
- Physical press fires a tap: disable the tap mapping and record diagnostics. Physical click interception is unsupported; no reliability claim is made for inter-stream timing before hardware tests.
- Volume unsupported: some outputs expose no software volume or mute. Use that device's hardware controls.
- Invalid configuration: preserve/back up the file, repair JSON/ranges/version, then reimport or restart. Errors do not authorize overwriting the original without backup.
- Start at Login fails: install in Applications first; inspect General → Login Items in System Settings. No launch-on-login behavior has been physically tested in this build environment.

## Uninstall and rollback

Turn OFF **General → Start at Login**, then run:

```sh
./uninstall.sh                                  # defaults to ~/Applications/EvenBetterTouchTool.app
./uninstall.sh /Applications/EvenBetterTouchTool.app     # if installed system-wide
```

The uninstaller unregisters the app's login item and removes only the identified EvenBetterTouchTool app. Configuration, migration backups, and original CLI binaries remain. Remove stale privacy entries and restore native trackpad gestures manually. To remove settings later, delete only `~/.config/threefinger.json` and the specific migration backups you no longer need. The old daemon is never automatically restarted. For rollback, restore your saved original config and LaunchAgent from the migration backup and bootstrap only that original service after quitting/removing the app.
