import AppKit
import SwiftUI
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var model: AppModel!
    private var hotkey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var lockDescriptor: Int32 = -1
    private let volumeIndicator = VolumeIndicator()
    private let preview = CommandLine.arguments.contains("--ui-preview")
    func applicationDidFinishLaunching(_ notification: Notification) {
        let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/org.evenbettertouchtool.app")
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        lockDescriptor = Darwin.open(cache.appendingPathComponent(preview ? "preview.lock" : "instance.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: "org.evenbettertouchtool.app") where app.processIdentifier != getpid() { app.activate(options: []) }
            NSApp.terminate(nil); return
        }
        if preview {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("evenbettertouchtool-ui-preview/config.json")
            let store = ConfigurationStore(url: url); var c = Configuration.defaults; c.enabled = false; try? store.save(c)
            model = AppModel(configurationURL: url)
        } else { model = AppModel() }
        NSApp.setActivationPolicy(model.config.menuBarOnly ? .accessory : .regular)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "EvenBetterTouchTool gesture controls")
        item.button?.toolTip = "EvenBetterTouchTool • Control–Option–Command–Escape disables gestures"
        let menu = NSMenu()
        menu.addItem(withTitle: "Enable / Disable Gestures", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Diagnostics…", action: #selector(diagnostics), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit EvenBetterTouchTool", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu; statusItem = item
        volumeIndicator.onVisibilityChanged = { [weak self, weak item] visible in
            item?.length = visible ? NSStatusItem.variableLength : NSStatusItem.squareLength
            self?.model.volumeIndicatorVisible = visible
        }
        model.onVolumeFeedback = { [weak self] level in
            guard let self else { return }; self.statusItem?.length = NSStatusItem.variableLength
            self.volumeIndicator.show(level,anchoredTo:self.statusItem?.button)
        }
        installMainMenu()
        installEmergencyHotkey()
        if !preview { model.start() }
        else { model.engineStatus = "UI preview — gesture engine not started"; model.foregroundChanged(); model.checkPermissions(); model.scanApplications() }
        if preview || CommandLine.arguments.contains("--open-settings") || !model.savedConfig.safety.nativeConflictsResolved { openSettings() }
    }
    @objc private func toggle() { model.toggleFromMenu(); if model.hasPendingChanges { openSettings() } }
    @objc private func openSettings() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsRoot(model: model))
            let w = NSWindow(contentViewController: host)
            w.title = "EvenBetterTouchTool"; w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 1080, height: 780)); w.minSize = NSSize(width: 940, height: 660)
            w.center(); w.isReleasedWhenClosed = false; w.delegate = self; window = w
        }
        model.setSettingsVisible(true)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) { model.setSettingsVisible(false) }
    @objc private func diagnostics() { model.section = "Diagnostics"; openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
        volumeIndicator.hide()
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if lockDescriptor >= 0 { close(lockDescriptor) }
    }
    private func installMainMenu() {
        let bar = NSMenu()
        let applicationItem = NSMenuItem(), applicationMenu = NSMenu(title: "EvenBetterTouchTool")
        applicationMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit EvenBetterTouchTool", action: #selector(quit), keyEquivalent: "q").target = self
        applicationItem.submenu = applicationMenu; bar.addItem(applicationItem)
        let editItem = NSMenuItem(), edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; bar.addItem(editItem)
        let settingsItem = NSMenuItem(), settings = NSMenu(title: "Settings")
        for section in ["Dashboard", "Gestures", "Applications", "Sensitivity", "Trackpad Calibration", "Setup Assistant", "General", "Diagnostics"] {
            let item = settings.addItem(withTitle: section, action: #selector(showSection(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = section
        }
        settings.addItem(.separator())
        settings.addItem(withTitle: "Save Changes", action: #selector(saveSettings), keyEquivalent: "s").target = self
        settings.addItem(withTitle: "Reset Changes", action: #selector(resetSettings), keyEquivalent: "").target = self
        settings.addItem(.separator())
        settings.addItem(withTitle: "Close Settings", action: #selector(closeSettings), keyEquivalent: "w").target = self
        settingsItem.submenu = settings; bar.addItem(settingsItem); NSApp.mainMenu = bar
    }
    @objc private func showSection(_ sender: NSMenuItem) { if let section = sender.representedObject as? String { model.section = section }; openSettings() }
    @objc private func saveSettings() { if model.canSave && model.calibrationAxis == nil { _ = model.save() } }
    @objc private func resetSettings() { model.resetEdits() }
    @objc private func closeSettings() { window?.performClose(nil) }
    private func installEmergencyHotkey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(data).takeUnretainedValue()
            delegate.model.emergencyDisable()
            return noErr
        }, 1, &eventType, pointer, &eventHandler)
        let status = RegisterEventHotKey(53, UInt32(cmdKey | controlKey | optionKey), EventHotKeyID(signature: 0x54464752, id: 1), GetApplicationEventTarget(), 0, &hotkey)
        if handlerStatus != noErr || status != noErr { model.message = "Emergency shortcut could not register (possibly in use). Use the menu bar switch to disable gestures." }
    }
}
