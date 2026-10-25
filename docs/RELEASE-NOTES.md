# EvenBetterTouchTool 2.1.1 — installer revision 1

This is an installer-only update. The app binary remains version 2.1.1 with the same signing identity.

- Installation automatically creates an EvenBetterTouchTool shortcut in the main Applications folder. If that location is unavailable or contains an unrelated item, it uses a desktop shortcut instead.
- Repeat installations and updates keep a correct existing shortcut, pointing to the same installed app.
- The installer registers the installed app with macOS for normal launching.
- Uninstall removes only shortcuts that point to the app being removed, preserving unrelated apps, aliases, files, and saved settings.
- A signed native helper is bundled, so downloaded installations do not need Xcode or AppleScript/Automation access to create the shortcut.

Download the ZIP, extract it, and run Install.command. Then launch from Finder → Applications → EvenBetterTouchTool, or the desktop shortcut. You can drag that icon into the Dock for one-click launching.

Validation: 107 core tests, 15 app-model tests, and 14 native shortcut lifecycle tests (136 total). The shortcut tests cover fresh installs, repeat installs, replacing the target app, fallbacks/conflicts, and safe cleanup.

The application remains experimental, ad-hoc signed, and unnotarized. Physical trackpad/media/audio/lifecycle acceptance tests remain outstanding. This packaging change does not modify the app’s gesture settings or code identity.
