# EvenBetterTouchTool 2.2.1 — Continuous shortcut editing

Imported single-shortcut mappings were stored as Sequence actions. The editor incorrectly disabled Continuous for every Sequence, preventing these mappings from using distance-based repetition.

- A Sequence containing one shortcut now supports Continuous, including migrated threefinger settings.
- A single application-specific shortcut can also repeat when the foreground app matches its target.
- The editor, gesture grid, and recognizer share the same parameter-aware capability rule. Multi-step sequences remain one trigger per swipe; the editor explains why Continuous is unavailable.
- Inherited app mappings offer Customize for This App before editing. Closing without Save still discards changes; Save commits only that gesture.

This update preserves saved mappings and does not enable Continuous automatically. Open the desired swipe, enable Continuous, and click Save. Movement uses the current relative or measured interval; no time repeat, momentum, or queued sequence repetition is added.

The app is experimental, ad-hoc signed, and unnotarized. macOS may require fresh Accessibility/Input Monitoring approval for the changed build. Actual shortcut delivery still needs physical testing; all 153 automated checks pass (119 core, 20 app-model, 14 installer), along with build/signing/smoke checks. Details are recorded in VALIDATION.md.
