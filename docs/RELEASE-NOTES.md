# EvenBetterTouchTool 2.1.0 — settings quality-of-life update

- Gesture popovers close using the new X button, Escape, or an outside click. Dismissing discards unsaved local edits.
- Replaced Done with a blue **Save** button. Gesture Save commits just that cell; unrelated pending edits remain pending.
- Added global Save/Reset controls across every settings page. Sensitivity, enable switches, profiles, setup, calibration, imports, restored defaults, and Start at Login do not apply or persist until Save. Quit never autosaves.
- Added Reset in gesture editors; Restore Default also stays local until Save.
- The Fingers hand switches stage an entire row on/off with dimmed cells and On/Off indicators. Re-enabling preserves individual mappings.
- The top master switch reads **Enabled** or **Disabled** according to its selection.
- Shortened labels and rebuilt slider rows to avoid wrapping and cramped spacing. A sequence delay appears only when multiple shortcuts need it.
- Protected pending edits from external configuration changes. Emergency pause still stops actions immediately without writing settings.

Download `EvenBetterTouchTool-2.1.0-arm64.zip`, extract it, and run `Install.command` or `./install.sh`. Requires Apple Silicon and macOS 14+. Open the hand icon in the menu bar → Open Settings. Complete required permissions/setup/calibration and click Save.

Validation: 97 core tests and 12 app-model tests pass, along with compilation, signature, metadata, and installer syntax checks. Popover dismissal, Reset, Save isolation, row indicators, pending sensitivity edits, and dynamic master labels were checked in an isolated disabled preview.

This remains an **experimental, ad-hoc signed, unnotarized** release using private MultitouchSupport APIs. Physical trackpad/media/audio/lifecycle acceptance testing is still outstanding. Physical multi-finger click remapping remains disabled; native macOS gesture conflicts require manual setup. Existing configurations remain compatible.
