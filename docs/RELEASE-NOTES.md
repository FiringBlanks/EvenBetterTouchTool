# EvenBetterTouchTool 2.5.1 — Responsive volume and complete action menus

- Assigned action uses five compact category submenus for every gesture, including four-finger click. Choices no longer hide above a long menu’s scroll position. Save and Reset behavior is unchanged.
- Volume fill updates immediately, without a native progress-bar animation trailing the actual percentage. The stable anchor and interaction fade remain.
- Forward movement retains every increment after direction lock, including a tiny final increment completing a distance interval. Jitter filtering remains on direction reversals.
- Continuous volume batches bypass synthetic-key rate/burst limits and use one Core Audio adjustment for all intervals. An optional volume cooldown retains steps until subsequent movement after it ends; stationary fingers never repeat. Chrome’s 0.05-second cooldown is preserved.
- Saved mappings, thresholds, calibration, and profiles are preserved. Uncalibrated distances remain percentages of each trackpad axis.

All 231 automated checks pass (182 core, 31 app-model/executor, 14 installer, four native volume-panel checks). The action submenus and editor Reset were verified in an isolated disabled preview. Physical volume responsiveness and distance acceptance still require on-device testing. Locally ad-hoc signed updates can require renewed Accessibility and Input Monitoring approval; the application never grants permissions itself.
