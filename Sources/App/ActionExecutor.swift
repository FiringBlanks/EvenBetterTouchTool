import AppKit
import ApplicationServices
import CoreAudio

/// All side effects live here. Recognition and action planning are independently testable.
final class ActionExecutor {
    static let eventTag: Int64 = 0x746872656566
    var report: (String) -> Void = { _ in }
    var volumeChanged: (VolumeLevel) -> Void = { _ in }
    private var sequenceGeneration = 0
    private var lastBudgetTime = 0.0
    private var budget = 0
    private let isTrusted: () -> Bool
    private let adjustVolume: (Double) throws -> VolumeLevel
    init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }, adjustVolume: @escaping (Double) throws -> VolumeLevel = SystemAudio.adjust) {
        self.isTrusted = isTrusted; self.adjustVolume = adjustVolume
    }
    func cancel() { sequenceGeneration += 1; sequenceActive = false }
    func execute(_ trigger: GestureTrigger, app: String, config: Configuration) {
        guard isTrusted() else { report("Accessibility permission required"); return }
        let commands = ActionPlanner.commands(trigger.mapping.action, app: app, sensitivity: config.sensitivity(for: app))
        // A whole volume batch is one Core Audio adjustment, not synthetic
        // input. Neither its distance count nor other actions consume its budget.
        if commands.count == 1, case .volume(let delta) = commands[0] {
            report(trigger.mapping.action.kind.title)
            perform(.volume(delta*Double(trigger.count)),config:config); return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now-lastBudgetTime >= 1 { budget = 0; lastBudgetTime = now }
        guard budget + trigger.count <= 120 else { report("Input rate limit reached; excess distance discarded"); return }
        budget += trigger.count
        if app == "com.apple.finder", [.previousTab, .nextTab].contains(trigger.mapping.action.kind), !finderHasTabs() {
            report("Finder: no eligible tabbed focused window"); return
        }
        if commands.count > 1 {
            // A sequence never overlaps another sequence and is cancelled by any settings/app change.
            guard !sequenceActive else { report("Previous shortcut sequence is still running"); return }
            sequenceActive = true
            let generation = sequenceGeneration
            runSequence(commands, index: 0, generation: generation, app: app, config: config)
            return
        }
        if !commands.isEmpty { report(trigger.mapping.action.kind.title) }
        for _ in 0..<trigger.count { for c in commands { perform(c, config: config) } }
    }
    private var sequenceActive = false
    private func runSequence(_ commands: [ActionCommand], index: Int, generation: Int, app: String, config: Configuration) {
        guard generation == sequenceGeneration else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app, index < commands.count else { sequenceActive = false; return }
        perform(commands[index], config: config)
        let delay: Double
        if case .shortcut(let s) = commands[index] { delay = max(0.01, s.delay) } else { delay = 0.04 }
        DispatchQueue.main.asyncAfter(deadline: .now()+delay) { [weak self] in self?.runSequence(commands, index: index+1, generation: generation, app: app, config: config) }
    }
    private func perform(_ command: ActionCommand, config: Configuration) {
        switch command {
        case .shortcut(let shortcut): post(shortcut)
        case .media(let key):
            for down in [true, false] {
                let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00), timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: ActionPlanner.mediaData(key: key, down: down), data2: -1)
                event?.cgEvent?.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
                event?.cgEvent?.post(tap: .cghidEventTap)
            }
        case .volume(let delta): do { volumeChanged(try adjustVolume(delta)) } catch { report(error.localizedDescription) }
        case .mute: do { try SystemAudio.toggleMute() } catch { report(error.localizedDescription) }
        case .mouse(let button):
            guard let source = CGEventSource(stateID: .hidSystemState), let position = CGEvent(source: nil)?.location, let mouse = CGMouseButton(rawValue: UInt32(button)) else { return }
            let types: [CGEventType] = button == 0 ? [.leftMouseDown, .leftMouseUp] : button == 1 ? [.rightMouseDown, .rightMouseUp] : [.otherMouseDown, .otherMouseUp]
            for t in types { let e = CGEvent(mouseEventSource: source, mouseType: t, mouseCursorPosition: position, mouseButton: mouse); e?.setIntegerValueField(.eventSourceUserData, value: Self.eventTag); e?.setIntegerValueField(.mouseEventClickState, value: 1); e?.post(tap: .cghidEventTap) }
        case .open(let id, let activateOnly):
            guard !id.isEmpty else { report("Choose an application first"); return }
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { app.activate(options: []) }
            else if !activateOnly, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in if let error { DispatchQueue.main.async { self?.report(error.localizedDescription) } } }
            } else { report("Application is not running or not installed") }
        case .system(let kind):
            let choice = SystemShortcuts.choice(kind)
            if let s = choice.shortcut(fallback:config.systemShortcuts[kind.rawValue]) {
                post(s); report("Sent \(kind.title): key \(s.keyCode), \(s.modifiers.joined(separator:" + "))")
            } else if choice == .disabled { report("\(kind.title) keyboard shortcut is disabled in macOS. Enable it in Keyboard Shortcuts.") }
            else { report("No shortcut for \(kind.title). Verify it in macOS, then configure Setup → Advanced → System shortcuts and Save.") }
        }
    }
    private func post(_ s: Shortcut) {
        let events = KeyboardEvents.make(s,physical:CGEventSource.flagsState(.hidSystemState))
        if events.isEmpty { report("Could not construct keyboard events"); return }
        for event in events { event.post(tap:.cghidEventTap) }
    }
    private func finderHasTabs() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == "com.apple.finder" else { return false }
        let started = ProcessInfo.processInfo.systemUptime
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.015)
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.015)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focused) == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let window = unsafeBitCast(focused, to: AXUIElement.self)
        // Fail closed if Finder's accessibility hierarchy changes. Only a tab group
        // in this window with at least two tab controls is eligible.
        var queue = [(window, 0)], index = 0
        while index < queue.count && index < 120 {
            guard ProcessInfo.processInfo.systemUptime-started < 0.05 else { return false }
            let (node, depth) = queue[index]; index += 1
            var role: CFTypeRef?, children: CFTypeRef?
            AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &children)
            let kids = children as? [AXUIElement] ?? []
            if role as? String == kAXTabGroupRole as String {
                let tabs = kids.filter { child in
                    var r: CFTypeRef?; AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &r)
                    return [kAXRadioButtonRole as String, "AXTab"].contains(r as? String ?? "")
                }
                if tabs.count >= 2 { return ProcessInfo.processInfo.systemUptime-started < 0.07 }
            }
            if depth < 5 { queue.append(contentsOf: kids.map { ($0, depth+1) }) }
        }
        return false
    }
}
/// Build the complete balanced sequence before posting any modifier down.
/// Tests inspect actual Quartz event flags without injecting input.
enum KeyboardEvents {
    static func make(_ shortcut: Shortcut, physical: CGEventFlags = []) -> [CGEvent] {
        var held = Set<String>()
        for (name,flag): (String,CGEventFlags) in [("control",.maskControl),("option",.maskAlternate),("shift",.maskShift),("command",.maskCommand),("fn",.maskSecondaryFn)] where physical.contains(flag) { held.insert(name) }
        guard let source = CGEventSource(stateID:.hidSystemState) else { return [] }
        var events = [CGEvent]()
        for stroke in KeyboardPlan.strokes(shortcut,held:held) {
            var flags = CGEventFlags()
            for m in stroke.modifiers {
                switch m { case "command": flags.insert(.maskCommand); case "shift": flags.insert(.maskShift); case "option": flags.insert(.maskAlternate); case "control": flags.insert(.maskControl); case "fn": flags.insert(.maskSecondaryFn); default: break }
            }
            if stroke.navigation { flags.formUnion([.maskSecondaryFn,.maskNumericPad]) }
            if stroke.function { flags.insert(.maskSecondaryFn) }
            guard let event = CGEvent(keyboardEventSource:source,virtualKey:stroke.key,keyDown:stroke.down) else { return [] }
            event.flags = flags; event.setIntegerValueField(.eventSourceUserData,value:ActionExecutor.eventTag)
            events.append(event)
        }
        return events
    }
}
enum SystemShortcuts {
    // These symbolic IDs are private preference schema, not an interception API.
    // Read explicit user settings only; absent/disabled entries require a verified fallback.
    static let ids: [ActionKind: String] = [.missionControl:"32", .appExpose:"33", .showDesktop:"36", .previousDesktop:"79", .nextDesktop:"81"]
    static func resolve(_ kind: ActionKind) -> Shortcut? {
        choice(kind).shortcut(fallback:nil)
    }
    static func choice(_ kind: ActionKind) -> SystemShortcutChoice {
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
        guard let id = ids[kind], let dict = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any],
              let entry = dict[id] as? [String: Any] else { return .unavailable }
        return SystemShortcutChoice.read(entry)
    }
}
enum SystemAudio {
    private static func defaultDevice() throws -> AudioDeviceID {
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &device) == noErr, device != 0 else { throw ConfigError.invalid("No default audio output device") }
        return device
    }
    private static func writable(_ device: AudioDeviceID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        var settable = DarwinBoolean(false)
        return AudioObjectHasProperty(device, &address) && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }
    @discardableResult static func adjust(_ delta: Double) throws -> VolumeLevel {
        let device = try defaultDevice()
        var elements: [UInt32] = []
        var main = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if writable(device, &main) { elements = [0] }
        else {
            // Only use channels actually exposed by the current output stream.
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeOutput, mElement: 0)
            var bytes: UInt32 = 0
            if AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &bytes) == noErr, bytes >= MemoryLayout<AudioBufferList>.size {
                let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(bytes), alignment: MemoryLayout<AudioBufferList>.alignment); defer { raw.deallocate() }
                if AudioObjectGetPropertyData(device, &streams, 0, nil, &bytes, raw) == noErr {
                    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
                    let count = list.reduce(0) { $0 + Int($1.mNumberChannels) }
                    if count > 0 { elements = (1...UInt32(count)).filter { channel in var a = main; a.mElement = channel; return writable(device, &a) } }
                }
            }
        }
        guard !elements.isEmpty else { throw ConfigError.invalid("This output device does not support software volume; use its hardware controls") }
        for e in elements {
            var a = main; a.mElement = e
            var volume: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &volume) == noErr else { throw ConfigError.invalid("Unable to read output volume") }
            volume = ActionPlanner.volume(volume, delta: delta)
            guard AudioObjectSetPropertyData(device, &a, 0, nil, size, &volume) == noErr else { throw ConfigError.invalid("Audio output rejected volume change") }
        }
        var sum = 0.0
        for e in elements {
            var a = main; a.mElement = e
            var volume: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device,&a,0,nil,&size,&volume) == noErr else { throw ConfigError.invalid("Volume changed, but its value could not be read back") }
            sum += Double(volume)
        }
        var muteAddress = AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyMute,mScope:kAudioDevicePropertyScopeOutput,mElement:0)
        var mute: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(device,&muteAddress,0,nil,&size,&mute)
        return VolumeLevel(value:sum/Double(elements.count),muted:mute != 0)
    }
    static func toggleMute() throws {
        let device = try defaultDevice()
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: 0)
        guard writable(device, &a) else { throw ConfigError.invalid("This output device does not support software mute") }
        var muted: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &muted) == noErr else { throw ConfigError.invalid("Unable to read output mute") }
        muted = muted == 0 ? 1 : 0
        guard AudioObjectSetPropertyData(device, &a, 0, nil, size, &muted) == noErr else { throw ConfigError.invalid("Audio output rejected mute change") }
    }
}
