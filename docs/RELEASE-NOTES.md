# EvenBetterTouchTool 2.5.0 — Stable volume feedback and gesture swaps

- Volume feedback keeps one anchor for its whole visible session. A fixed-width status item prevents the percentage from shifting the menu bar layout repeatedly; updates reuse the existing view.
- Other interaction starts a short fade: mouse movement/buttons/drag, keyboard/modifiers, normal scrolling, app changes, and other gestures/actions. Active volume gestures keep updating the panel. It still fades after two idle seconds; new volume input can cancel a fade without a stale completion hiding the panel.
- Six small ↕ buttons between the three/four-finger rows swap that column's complete mappings. Profile swaps resolve inherited values without changing globals or other profiles. Row toggles stay attached to their finger counts. Swaps remain pending until Save, and Reset restores the saved mappings.

All 224 automated checks pass: 177 core, 29 app-model, 14 installer, and four native volume-panel tests. The native tests check fixed frames across 9%/99%/100% updates, interaction fade, revival during a fade, and idle timeout. They show simulated percentages without changing system audio or injecting input. Visual inspection of the new grid and live mouse/gesture dismissal are manual acceptance checks.

The release remains experimental, ad-hoc signed, and unnotarized. Existing saved settings are preserved. Updating the installed binary may require fresh Accessibility and Input Monitoring approval.
