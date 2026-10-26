# EvenBetterTouchTool 2.5.2 — Deliberate pointer dismissal

- The volume indicator starts fading early only after the pointer moves at least 24 logical screen points away from its location at the latest volume adjustment. Small repeated wobbles do not accumulate.
- Adding/removing fingers, other gestures, typing, scrolling, clicks without movement, and app changes no longer dismiss it early. Only movement/drag events are monitored while feedback is visible.
- New volume adjustments reset the pointer reference and can revive a fade. The existing two-second idle fade, stable position, and immediate bar updates remain.
- Native display-only volume HUD compatibility was investigated on Tahoe, but visual success was not confirmed. The working custom indicator is retained; no extra volume keys or private HUD calls ship.
- Saved mappings, sensitivity, and profiles are preserved. No settings are saved implicitly.

All 237 checks pass: 187 core, 31 app-model/executor, 14 installer, and five native panel checks. Physical pointer/finger transitions remain manual acceptance checks. Local ad-hoc updates may need fresh Accessibility and Input Monitoring approvals.
