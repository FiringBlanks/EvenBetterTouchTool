# Getting custom gestures running

The Enabled switch selects the master setting. It does not mean macOS has granted permission or that trackpad setup is complete. Dashboard lists the actual blockers under Gesture readiness; Ready custom mappings stays at zero while required permissions or setup are missing.

## Add the correct application

1. Open the installed EvenBetterTouchTool and go to Dashboard → Permissions.
2. Click **Copy App Path**. It copies the location of the running `.app`, so you do not accidentally grant an old build or the original daemon.
3. Click **Set Up…** for Input Monitoring. The app requests access and opens System Settings → Privacy & Security → Input Monitoring.
4. An empty “No Items” list is not an error. Click **+** to choose an application.
5. In the file picker, press **Command–Shift–G**, paste the copied application path, and press Return. Select the app if necessary, then click **Open**. The default installed location is `~/Applications/EvenBetterTouchTool.app` (your personal Applications folder, not necessarily `/Applications`). You can also use Show App in Finder to locate it.
6. Enable EvenBetterTouchTool’s switch and complete any macOS authentication prompt yourself.
7. Repeat for Accessibility if needed. Grant the installed `.app`, not a binary inside `Contents/MacOS`, an old build directory, Terminal, or the original `threefinger` utility.
8. Save or Reset pending app edits, then use **Relaunch App**. Recheck Permissions reports what this new running process can actually use.

If Accessibility already looks enabled but the app still says Not verified, first relaunch. If it remains unverified, select the old EvenBetterTouchTool entry, remove it with **−**, then add the current installed copy using the same path steps and enable it again. This local release is ad-hoc signed: changed builds can have a different code identity despite keeping the same name/bundle ID. An old enabled privacy entry may therefore not apply to the current build. A consistent proper code-signing identity is needed for durable grant continuity across changed releases. The installer never grants or resets permissions automatically.

Apple references: [Input Monitoring](https://support.apple.com/guide/mac-help/mchl4cedafb6/mac), [Accessibility access](https://support.apple.com/guide/mac-help/mh43185/mac), [Go to Folder](https://support.apple.com/guide/mac-help/mchlp1236/mac).

## Finish the app's saved setup

Permissions alone do not remove the other safety gates:

- In Setup Assistant, manually resolve the listed native gesture conflicts in macOS. Only then check the corresponding confirmations and click **Save**. The app cannot suppress native gestures automatically.
- In Trackpad Calibration, measure the active X/Y scales with a ruler or supply measured active-surface dimensions. Click **Use Measurement** after each trial, then **Save**. Normalized/raw sensor coordinates are not millimeters; no device dimensions are assumed.
- Custom taps also require their separate native tap conflict confirmation and a working physical-button observer.
- Settings and measurements remain pending until Save. The sidebar and Dashboard report saved readiness, even while an unsaved master switch says Enabled.
- Default tab navigation applies to Chrome and Finder profiles. Original legacy mappings are preserved; restore the desired profile/cells and Save to adopt continuous tab actions.

Readiness can be tested in Diagnostics after these steps. Raw contact data may be visible before permissions are verified, but the app keeps synthetic custom actions paused. This is intentional. The blue master switch remains blue when its window loses focus; that color indicates its selected value, not permission status.
