# EvenBetterTouchTool 2.0.0 — initial experimental release

Free, MIT-licensed macOS menu bar trackpad customization, based on firedev/threefinger.

## Download and install

Download `EvenBetterTouchTool-2.0.0-arm64.zip`, extract it, and run `Install.command` or `./install.sh`. Requires Apple Silicon and macOS 14 or later. The app is included in the ZIP; Xcode is only needed to build from source.

Open the hand icon in the menu bar → **Open Settings**. Complete Setup Assistant, grant the installed app Accessibility and Input Monitoring, and calibrate X/Y physical distance. Settings save automatically. Start at Login is optional in General.

## Included

- Native SwiftUI menu bar app and settings window, branded EvenBetterTouchTool throughout.
- Three/four-finger swipes and taps with app profiles, a gesture grid, sensitivity controls, and diagnostics.
- Continuous calibrated tab and volume actions with fractional movement, reversals, and no timed repeat.
- Dedicated system media commands, Core Audio volume/mute, shortcuts/sequences, application and navigation actions.
- Native desktop swipe pass-through by default, explicit conflict setup, emergency disable, atomic settings, and backed-up migration from the original threefinger utility.
- Local installer/uninstaller and complete source under the upstream MIT license.

## Verification and limitations

The Apple Silicon app builds successfully and all 80 automated core tests pass. The settings UI was inspected in an isolated disabled preview. Hardware trackpad accuracy, Finder accessibility eligibility, media delivery, audio-device behavior, sleep/wake, privacy revocation, and actual login startup still need acceptance tests.

This is an **experimental, ad-hoc signed, unnotarized** release. It uses private MultitouchSupport APIs that can change with macOS. The installer does not bypass macOS security controls. Physical multi-finger click remapping is disabled; Notification Center requires a user-configured keyboard shortcut. Native gesture suppression is not provided—follow the setup assistant to resolve conflicts manually.

Emergency global disable: **Control–Option–Command–Escape**, or the menu bar switch.
