# EvenBetterTouchTool — macOS trackpad customization

A free, MIT-licensed native SwiftUI menu bar app built from [firedev/threefinger](https://github.com/firedev/threefinger). Customize three- and four-finger gestures with app profiles, continuous relative or calibrated movement, media controls, Core Audio volume, and a graphical setup/diagnostics interface. No subscriptions, dependencies, analytics, or network updater.

**Requires macOS 14+, Apple Silicon, and Xcode Command Line Tools to build.** The raw contact driver uses Apple's private MultitouchSupport framework; future OS compatibility is not guaranteed. Physical multi-finger click remapping is disabled. See [compatibility and API investigation](docs/COMPATIBILITY.md) before enabling custom input.

## Download and change settings

Download the [Apple Silicon release ZIP](https://github.com/FiringBlanks/EvenBetterTouchTool/releases/download/v2.2.0/EvenBetterTouchTool-2.2.0-arm64.zip) from [GitHub Releases](https://github.com/FiringBlanks/EvenBetterTouchTool/releases). Extract it and run `Install.command` (or `./install.sh` in Terminal). The installer places the app in your personal Applications folder, creates a launch shortcut in the main Applications folder (or on the desktop if that folder is unavailable), and safely stops the original threefinger service if present. The app is also included directly in the ZIP.

After installation, open **Finder → Applications → EvenBetterTouchTool** (or the desktop shortcut). Drag that icon into the Dock if you want one-click access. The shortcut opens the installed app.

Open **EvenBetterTouchTool** from Applications. Click its **hand icon in the menu bar → Open Settings**. In **Gestures**, choose Global or an app profile, then click a gesture cell to change its action. Use **Applications** for per-app overrides and **Sensitivity** for distance/tap settings. Edits stay pending until you click **Save**. **Reset** discards pending edits. Complete Setup Assistant and permissions before using custom input. Calibration is optional.

This release is **experimental, locally ad-hoc signed, and not notarized**. Physical trackpad acceptance tests are still pending; see the compatibility and test documents below. macOS may require you to explicitly allow the downloaded app through its normal Privacy & Security controls. The installer does not bypass Gatekeeper or change privacy/gesture preferences.

## Build and install locally

```sh
cd /path/to/EvenBetterTouchTool
make check       # compile, automated tests, signature/plist/script checks
make package     # installable ZIP plus SHA-256 checksum
./install.sh --dry-run
./install.sh
```

The compiled app is `build/EvenBetterTouchTool.app`. Installation defaults to `~/Applications/EvenBetterTouchTool.app`. Use `./install.sh --destination /Applications` if you prefer the system Applications folder and have write access. The package is `build/EvenBetterTouchTool-2.1.1-arm64.zip`; unzip and run the included `Install.command` or `install.sh`. It contains the built app and a signed standalone shortcut helper, so it does not need to download anything or require Xcode to create the shortcut. This installer revision keeps the app itself at version 2.1.1; its app binary and signing identity are unchanged. A `.dmg` is unnecessary: the ZIP includes a complete signed `.app`, installer, uninstaller, and documentation.

The installer stages and verifies the replacement **before** stopping the old utility. It creates the shortcut automatically after placing the app, keeps an existing correct shortcut on repeat installs/updates, registers the installed app for normal macOS launching, and preserves any unrelated item with the same name. A direct installation in `/Applications` needs no extra shortcut. It unloads the known original/Homebrew user LaunchAgents, archives their plists and existing config under `~/.config/threefinger-migration/`, then stops only exact-name same-user legacy processes. It preserves old CLI binaries, the Homebrew formula, configuration, and previous app backups. It refuses an unrelated app at the destination or a duplicate copy in the standard Applications locations. It never runs upstream `threefinger --reinstall` or downloads the original release. Root-owned/custom-labeled daemons must be stopped separately if you installed one yourself.

Do not run `brew services start/upgrade threefinger` alongside this app. If you no longer need the original Homebrew formula, uninstall it yourself after migration. The app detects a running original same-user daemon at startup and pauses custom actions; Diagnostics can recheck after migration. It also uses a per-user lock to prevent duplicate app engines.

### First launch

If no gestures work or a permission list says “No Items”, follow the [step-by-step permission and readiness guide](docs/PERMISSIONS.md). The file picker opened by + is normal; use Copy App Path and Command–Shift–G to select the running installed app.

1. Grant **EvenBetterTouchTool.app** Accessibility and Input Monitoring in System Settings → Privacy & Security. Use Dashboard or Setup Assistant to open/request these permissions. Quit/reopen after an Input Monitoring change. The old CLI daemon's grants do not transfer.
2. Complete **Setup Assistant**: turn native Mission Control/App Exposé trackpad swipes OFF, retain four-finger horizontal full-screen switching, restrict page swipes to two fingers or Off, and turn three-finger dragging OFF. Custom taps additionally require Look Up and Tap to click OFF. The full table and reasoning are in [COMPATIBILITY.md](docs/COMPATIBILITY.md). The app does not alter system preferences or suppress native gestures automatically.
3. Verify keyboard shortcuts for Mission Control and Application windows. If the app cannot read a configured shortcut, set a user-verified fallback under General → System Shortcuts. No Control–Arrow shortcut is silently assumed.
4. Start using gestures with **relative sensitivity**: intervals are a percentage of trackpad width/height, with no measurement required. In Sensitivity, adjust how far you move for each action. For exact millimeter thresholds, optionally expand **Trackpad Calibration → Precision calibration**, enter both measured dimensions and click **Use Measurements**, or measure X/Y with single-finger trials. Click Save. Raw normalized coordinates are never silently treated as millimeters.
5. Click **Save** to apply setup. Enable **Start at Login** under General and click Save if desired. macOS Login Items manages startup; no second LaunchAgent is installed.

**Emergency disable: Control–Option–Command–Escape.** The menu bar also provides Enable/Disable, Open Settings, Diagnostics, and Quit. If the emergency shortcut cannot register because another application owns it, the app warns you; use the menu bar switch.

## Default mappings

| Gesture | Default action |
| --- | --- |
| Three-finger left/right | Previous/next tab in Chrome and Finder profiles only; 1% of trackpad width per step (1 mm when calibrated) |
| Three-finger up/down | Mission Control / App Exposé, once per contact session |
| Three-finger tap | Dedicated system Play/Pause media command |
| Three-finger physical click | Middle click is the intended action but mapping is **disabled / unsupported** |
| Four-finger left/right | Native desktop gesture; sends no synthetic event |
| Four-finger up/down | Volume up/down, 2 percentage points per 4% of trackpad height (4 mm when calibrated) |
| Four-finger tap | Mute/unmute |
| Four-finger physical click | Unassigned and unsupported |

The defaults describe a fresh configuration. Migration preserves your existing explicit shortcut mappings as global one-shot sequences, including old Chrome/Finder overrides; it backs up the original JSON first. An old normalized threshold cannot be converted to mm without calibration and stays recorded in that backup. Restore an individual cell or app profile to adopt the new defaults.

Continuous gestures retain fractional intervals, reverse without lifting, and stop when movement stops. Distance intervals are adjustable from 0.5–20% of the relevant trackpad axis (0.5–20 mm when calibrated), globally, per app, or per mapping. Reversing discards the old direction's remaining fraction and starts at the turning point. There is no timed repeat or momentum. Exceptional input bursts are limited and discarded rather than replayed later; see compatibility notes.

## Settings and action library

The native settings window provides Dashboard, a 2×6 gesture grid with cell editors, installed-app profiles/icons, Sensitivity, Trackpad Calibration with live contacts, Setup Assistant, General, and Diagnostics. Native controls support light/dark appearances and accessibility labels. The app lives in the menu bar with no permanent Dock icon by default; Opening Settings temporarily shows the Dock icon and activates the app’s own menu bar, with Settings navigation, Save, Reset, and Close. Closing Settings returns to menu bar only operation; General can opt into permanent Dock visibility.

Profiles resolve **enabled application override → global mapping → no action/native pass-through**. A disabled app profile falls back to global; a disabled cell inside an enabled profile explicitly blocks that gesture. Unedited app cells inherit global mappings. Profile sensitivity is independently configurable. Additional applications initially have no tab behavior until you add a profile or global action.

Available actions include tab/desktop navigation, Mission Control, App Exposé, Show Desktop, recent-app switching, browser Back/Forward, system Play/Pause/Next/Previous Track, volume/mute, Lock Screen, screenshot UI, mouse down/up pairs, custom keyboard shortcuts and ordered sequences, opening/activating applications, target-app shortcuts, No Action, and native pass-through. Each action exposes relevant parameters. Notification Center has no reliable public opening API here: assign a custom user-configured system shortcut instead. Click-trigger mappings remain unavailable, but a middle-click **action** may be assigned to another supported gesture. Shortcut sequences and disruptive system actions run once per contact session.

Chrome uses Command–Option–Arrow. Finder uses Control–Tab / Control–Shift–Tab after a focused-window accessibility check for multiple tab controls; no eligible window means no action. Finder's hierarchy needs on-device validation. Media actions use dedicated system media events, **not F8**. Volume uses the current default output device's Core Audio properties and reports unsupported hardware volume/mute gracefully.

### Persistence

Configuration remains at `~/.config/threefinger.json` with `schemaVersion: 2`. All changes are drafts until you click **Save**, including sensitivity, row/profile toggles, master enable, startup at login, imports, restored defaults, calibration, and setup confirmations. The engine continues using saved settings while you edit. Each explicit Save backs up the existing file and writes atomically. Quitting, closing a popup, exporting saved settings, and opening the configuration file never save pending edits.

Gesture editors have a close button and dismiss when you click outside or press Escape; those dismissal paths discard local edits. The editor’s blue **Save** commits only that gesture and leaves unrelated edits pending. Its **Reset** restores the values from when the editor opened; **Restore Default** stages the default for that gesture. The main window’s **Reset** discards all pending changes, and its **Save** applies all remaining pending settings.

Click the hand in the **Fingers** column to stage enabling/disabling the entire three- or four-finger row. Disabled rows are dimmed and marked Off. Individual mappings are preserved when a row is re-enabled; unsupported clicks remain unsupported. Per-app row choices override global row choices. A row switch only gates custom actions; native macOS gestures cannot be disabled by this app.

Valid external JSON edits reload within two seconds. If an external edit arrives while drafts exist, the app retains them and asks you to Reset and review the saved configuration before saving, preventing accidental overwrites. Invalid external edits pause custom actions. Imported local consent/calibration is cleared, and imports remain pending until Save. Export writes only the saved configuration. **Emergency disable is immediate and temporary**; it never writes settings implicitly. Click Save to persist a disabled master switch.

Diagnostics displays raw contacts, movement with explicit % or mm units, recognized gesture, block/cancellation reason, action/result, foreground app, sensitivity, timestamp, and device status. Optional action logging is bounded to 250 in-memory entries; no typed content is logged. Copy Diagnostics puts current diagnostic information on the clipboard only when requested.

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
- `Sources/Core/GestureReadiness.swift`: explicit permission/setup blockers and privacy pane routes.
- `Sources/Core/SettingsDraft.swift`: pending edits, scoped gesture saves, external-edit conflicts, and row switches.
- `Sources/Core/GestureEngine.swift`: pure recognition and reusable command planning.
- `Sources/App/TrackpadDriver.swift`: runtime contact bridge, device selection, serial processing, button observation, lifecycle.
- `Sources/App/ActionExecutor.swift`: keyboard/media/mouse events, Finder checks, Core Audio, configured system shortcuts.
- `Sources/App/AppModel.swift`: live settings, permissions, profiles, calibration, diagnostics.
- `Sources/App/AppDelegate.swift`: app singleton, menu bar, window, emergency hotkey.
- `Sources/App/SettingsViews.swift`: native graphical interface.
- `Sources/Installer/LauncherManager.swift` and `main.swift`: standalone native Finder shortcut creation/resolution/cleanup.
- `Tests/LauncherTests.swift`: fresh/repeat install, replacement, fallback, and safe cleanup cases.
- `Tests/CoreTests.swift`: deterministic recognition/configuration/command/draft tests.
- `Tests/AppModelTests.swift`: save-only persistence, reset/import/quit/startup/emergency behavior against the actual app model.
- `Resources/`, `scripts/`, `Makefile`, `main.swift`: app metadata/icon, local packaging/migration, build and entry point.

Add new actions through `ActionKind`, `ActionPlanner`, the executor, and parameter controls; recognition does not depend on their system implementation. The callback copies only a bounded contact frame, processes on a serial queue, and publishes UI state at a limited rate. A single selected device prevents duplicate engines and cross-device mixing.

## Validation and troubleshooting

See [build/validation results and the file manifest](docs/VALIDATION.md). Run `make check` for automated results and [the manual acceptance checklist](docs/MANUAL-TESTS.md) for hardware testing. Tests exercise synthetic three/four-finger frames, directions, continuous distance, fractions/reversal, stationary input, taps/physical-button cancellation, invalid frames, profiles, action plans/media encodings/volume clamping, persistence/migration, and conflict gates. These are **not proof of hardware gesture accuracy or media delivery**.

- No actions: inspect Dashboard for permission, setup, selected-device, and legacy-daemon state. Lift all fingers after any app/settings change. Use Diagnostics for the exact block reason.
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

The uninstaller unregisters the app's login item, removes only Applications/desktop shortcuts that resolve to this installed app, and removes the identified EvenBetterTouchTool app. An unrelated app, alias, or file is preserved. You can pass the Applications shortcut itself to the uninstaller; it resolves to the real installed app first. Configuration, migration backups, and original CLI binaries remain. Remove stale privacy entries and restore native trackpad gestures manually. To remove settings later, delete only `~/.config/threefinger.json` and the specific migration backups you no longer need. The old daemon is never automatically restarted. For rollback, restore your saved original config and LaunchAgent from the migration backup and bootstrap only that original service after quitting/removing the app.
