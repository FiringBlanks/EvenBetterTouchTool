# EvenBetterTouchTool 2.4.1 — User-tested defaults

- Fresh configurations and restored Chrome app profiles use a 0.05-second cooldown for both three-finger horizontal swipe mappings. Continuous distance-based behavior stays enabled; movement during cooldown is discarded. Finder and unprofiled apps keep their prior defaults.
- Three-finger Click → Play/Pause is enabled by default, with three-finger Tap playback disabled. The original mouse click still occurs. The user confirmed this press mapping works on their Mac.
- Existing saved mappings, press tolerances, and cooldowns remain unchanged. Restore Defaults stages the new values until Save; Reset discards them.

This update changes configuration defaults only. The working local installation can remain on 2.4.0 to retain its existing OS approvals; source builds and downloads are 2.4.1. Installing the changed ad-hoc binary may require fresh Accessibility/Input Monitoring approval.

Build/signing/smoke checks and all 210 automated tests pass (169 core, 27 app-model, 14 installer).

The app remains experimental, ad-hoc signed, and unnotarized. Hardware confirmation is limited to the user's reported click playback result; other acceptance checks are documented separately.
