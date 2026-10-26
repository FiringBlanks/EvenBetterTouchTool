# EvenBetterTouchTool 2.4.0 — Physical press actions and forgiving taps

- Click mappings are now editable opt-in actions. An observed physical mouse down/up while three or four fresh trackpad contacts rest on the selected device fires once on release. The normal mouse click remains. An external mouse can also satisfy this correlation; exclusive click remapping is not claimed.
- The requested installed configuration enables three-finger Click → Play/Pause and keeps three-finger Tap playback disabled. Fresh public defaults leave press actions disabled until enabled.
- Forgiving tap defaults: 0.50 s contact, 0.15 s landing, 0.20 s release, 2 units of finger drift, 1.5 units of coherent movement cancelling the tap, and 0.25 s cooldown. A triggered swipe or physical press always cancels the tap. Units are measured millimeters or relative trackpad percentages.
- All tap timing, drift, swipe cancellation, cooldown, click checking/exclusion, and physical press recognition parameters are adjustable in Sensitivity and app overrides, plus individual Tap/Click editors. Settings remain pending until Save; Reset discards them.

Build/signing/smoke checks and 207 automated tests pass (167 core, 26 app-model, 14 installer). The disabled UI preview verified that Click can be enabled and saved, press parameters are editable, and forgiving tap overrides save while the tap remains disabled. Tests use synthetic contacts and mouse-button edges; actual trackpad press/media delivery still needs physical testing.

This release remains experimental, ad-hoc signed, and unnotarized. The changed app may need fresh Accessibility/Input Monitoring approval. Existing mappings, native settings, calibration, and unrelated sensitivities are preserved by installation.
