# EvenBetterTouchTool 2.2.0 — simpler setup and native app menus

- Opening Settings activates EvenBetterTouchTool’s macOS menu bar and temporarily shows its Dock icon. The Settings menu navigates sections and offers Save, Reset, and Close. Closing Settings returns to background operation when Menu Bar Only is enabled.
- Calibration is optional. Unmeasured trackpads use explicitly labeled percentages of trackpad width/height. Defaults are one tab per 1% horizontal movement and one 2-point volume step per 4% vertical movement. Recognition still depends on distance, stops when stationary, and reverses without lifting.
- Existing measured calibrations keep true millimeter thresholds. Precision calibration is collapsed by default. A clear Use Measurements button replaces the blocked confirmation switch; both measured dimensions must be 20–300 mm. Calibration edits and switching to relative units still require Save.
- Native gesture conflict setup and OS permission checks remain required. Calibration no longer blocks custom mappings.

This release changes the locally ad-hoc signed app binary. macOS may require removing the older privacy entry and granting this installed build Accessibility/Input Monitoring again. The installer preserves settings and measured calibrations; no native system preferences or permission grants are changed automatically.

Build, signing, smoke, metadata, and script checks pass, along with 113 core, 19 app-model, and 14 installer tests (146 total). Details are recorded in VALIDATION.md. Actual media/audio delivery, ruler accuracy, native gesture interactions, and lifecycle behavior still need the manual hardware checks. This release is experimental and not notarized.
