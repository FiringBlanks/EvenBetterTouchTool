import Foundation

enum Direction: String, Codable, CaseIterable { case left, right, up, down, tap, click
    var title: String { rawValue.capitalized }
    var isSwipe: Bool { self != .tap && self != .click }
}
struct Gesture: Hashable, Codable, Identifiable {
    var fingers: Int
    var direction: Direction
    var id: String { "\(fingers)_\(direction.rawValue)" }
    static let all = [3, 4].flatMap { n in Direction.allCases.map { Gesture(fingers: n, direction: $0) } }
    var title: String { "\(fingers)-finger \(direction.rawValue)" }
}
enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none, native, previousTab, nextTab, previousDesktop, nextDesktop, missionControl, appExpose, showDesktop
    case previousApplication, nextApplication, browserBack, browserForward
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute, lockScreen, screenshot, notificationCenter
    case leftClick, rightClick, middleClick, shortcut, sequence, openApplication, activateApplication, applicationShortcut
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "No Action"
        case .native: return "Native macOS / Pass Through"
        case .appExpose: return "App Exposé"
        case .playPause: return "Play / Pause"
        default: return rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
        }
    }
    var category: String {
        switch self {
        case .none, .native: return "Miscellaneous"
        case .previousTab, .nextTab, .previousDesktop, .nextDesktop, .missionControl, .appExpose, .showDesktop, .previousApplication, .nextApplication, .browserBack, .browserForward: return "Navigation"
        case .leftClick, .rightClick, .middleClick, .shortcut, .sequence: return "Mouse / Keyboard"
        case .openApplication, .activateApplication, .applicationShortcut: return "Applications"
        default: return "Media / System"
        }
    }
    var repeatable: Bool {
        [.previousTab, .nextTab, .browserBack, .browserForward, .volumeUp, .volumeDown, .shortcut].contains(self)
    }
}
struct Shortcut: Codable, Equatable {
    var keyCode: UInt16 = 48
    var modifiers: [String] = ["control"]
    var delay: Double = 0.04
}
struct Action: Codable, Equatable {
    var kind: ActionKind = .none
    var shortcuts: [Shortcut] = [Shortcut()]
    var bundleID: String = ""
    var volumePercent: Double? = nil
    /// Legacy imports represent even one keystroke as a sequence. A single
    /// command can repeat synchronously; timed multi-command sequences cannot.
    var supportsContinuous: Bool {
        if [.sequence, .applicationShortcut].contains(kind) { return shortcuts.count == 1 }
        return kind.repeatable && (kind != .shortcut || !shortcuts.isEmpty)
    }
    var continuousUnavailableReason: String? {
        guard !supportsContinuous else { return nil }
        if [.sequence, .applicationShortcut].contains(kind) {
            return "Continuous needs one shortcut. Multi-step sequences run once per swipe."
        }
        if kind == .none || kind == .native { return "Choose a custom action that can repeat to use Continuous." }
        if kind == .shortcut { return "Add a shortcut to use Continuous." }
        return "\(kind.title) runs once per swipe. Choose a shortcut, tab, browser, or volume action for Continuous."
    }
}
struct Mapping: Codable, Equatable {
    var enabled = true
    var action = Action()
    var continuous = false
    var distanceMM: Double? = nil
    var cooldown: Double = 0
    var reverse = false
    var tapOptions: TapOptions? = nil
    var clickOptions: ClickOptions? = nil
}
struct Sensitivity: Codable, Equatable {
    var horizontalMM = 1.0
    var verticalMM = 4.0
    var tapDuration = 0.50
    var tapToleranceMM = 2.0
    var activationMM = 0.5
    var diagonalRatio = 1.35
    var volumePercent = 2.0
    var jitterMM = 0.05
    var tapOptions: TapOptions? = nil
    var clickOptions: ClickOptions? = nil
    var effectiveTapOptions: TapOptions {
        get { tapOptions ?? TapOptions(duration:tapDuration,movement:tapToleranceMM) }
        set { tapOptions = newValue; tapDuration = newValue.duration; tapToleranceMM = newValue.movement }
    }
    var effectiveClickOptions: ClickOptions {
        get { clickOptions ?? ClickOptions() }
        set { clickOptions = newValue }
    }
}
struct Calibration: Codable, Equatable {
    var widthMM = 0.0
    var heightMM = 0.0
    var confirmed = false
    var dimensionsValid: Bool { widthMM.isFinite && heightMM.isFinite && (20...300).contains(widthMM) && (20...300).contains(heightMM) }
    var valid: Bool { confirmed && dimensionsValid }
}
/// Unmeasured devices use percentages of each axis, never assumed millimeters.
/// Existing *MM configuration keys are retained for profile compatibility.
struct MovementScale {
    var width: Double
    var height: Double
    var measured: Bool
    var unit: String { measured ? "mm" : "%" }
    var title: String { measured ? "Measured millimeters" : "Relative · % of trackpad" }
    init(_ calibration: Calibration?) {
        measured = calibration?.valid == true
        width = measured ? calibration!.widthMM : 100
        height = measured ? calibration!.heightMM : 100
    }
}
struct AppProfile: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String
    var enabled = true
    var mappings: [String: Mapping] = [:]
    var sensitivity: Sensitivity? = nil
    var rowEnabled: [String: Bool]? = nil
    var id: String { bundleID }
}
struct Safety: Codable, Equatable {
    var nativeConflictsResolved = false
    var nativeHorizontalDisabled = false
    var tapConflictsResolved = false
}
struct Configuration: Codable, Equatable {
    var schemaVersion = 2
    var enabled = true
    var menuBarOnly = true
    var logging = false
    var sensitivity = Sensitivity()
    var calibrations: [String: Calibration] = [:]
    var selectedDevice: String = ""
    var safety = Safety()
    var mappings: [String: Mapping] = [:]
    var profiles: [AppProfile] = []
    var rowEnabled: [String: Bool]? = nil
    // Explicit fallbacks are opt-in; the OS's configured shortcuts take precedence.
    var systemShortcuts: [String: Shortcut] = [:]
    static var defaults: Configuration {
        var c = Configuration()
        for g in Gesture.all {
            var m = Mapping()
            switch (g.fingers, g.direction) {
            case (3, .up): m.action.kind = .missionControl
            case (3, .down): m.action.kind = .appExpose
            case (3, .tap): m.action.kind = .playPause; m.enabled = false
            case (3, .click): m.action.kind = .playPause
            case (4, .left), (4, .right): m.action.kind = .native
            case (4, .up): m.action.kind = .volumeUp; m.continuous = true
            case (4, .down): m.action.kind = .volumeDown; m.continuous = true
            case (4, .tap): m.action.kind = .mute
            case (4, .click): m.enabled = false
            default: break
            }
            c.mappings[g.id] = m
        }
        c.profiles = [defaultProfile("com.google.Chrome", name: "Google Chrome"), defaultProfile("com.apple.finder", name: "Finder")]
        return c
    }
    static func defaultProfile(_ id: String, name: String) -> AppProfile {
        var p = AppProfile(bundleID: id, name: name)
        if ["com.google.Chrome", "com.apple.finder"].contains(id) {
            for d in [Direction.left, .right] {
                p.mappings[Gesture(fingers: 3, direction: d).id] = Mapping(action: Action(kind: d == .left ? .previousTab : .nextTab), continuous: true, cooldown: id == "com.google.Chrome" ? 0.05 : 0)
            }
        }
        return p
    }
    func profile(_ app: String) -> AppProfile? { profiles.first { $0.bundleID == app && $0.enabled } }
    func isRowEnabled(_ fingers: Int, app: String) -> Bool { profile(app)?.rowEnabled?[String(fingers)] ?? rowEnabled?[String(fingers)] ?? true }
    func mapping(_ g: Gesture, app: String) -> Mapping {
        var m = profile(app)?.mappings[g.id] ?? mappings[g.id] ?? Mapping(enabled: false)
        if !isRowEnabled(g.fingers, app: app) { m.enabled = false }
        return m
    }
    func sensitivity(for app: String) -> Sensitivity { profile(app)?.sensitivity ?? sensitivity }
    func movementScale(for device: String) -> MovementScale { MovementScale(calibrations[device]) }
    func tapOptions(fingers: Int, app: String) -> TapOptions {
        mapping(Gesture(fingers:fingers,direction:.tap),app:app).tapOptions ?? sensitivity(for:app).effectiveTapOptions
    }
    func clickOptions(fingers: Int, app: String) -> ClickOptions {
        let mapping = mapping(Gesture(fingers:fingers,direction:.click),app:app)
        var options = mapping.clickOptions ?? sensitivity(for:app).effectiveClickOptions
        options.cooldown = max(options.cooldown,mapping.cooldown)
        return options
    }
    func scrollInterceptedGestures(app: String, device: String) -> Set<Gesture> {
        Set(Gesture.all.filter { physical in
            guard physical.direction.isSwipe else { return false }
            var target = physical, mapping = self.mapping(physical,app:app)
            if mapping.reverse {
                switch physical.direction { case .up: target.direction = .down; case .down: target.direction = .up; case .left: target.direction = .right; case .right: target.direction = .left; default: break }
                mapping.action = self.mapping(target,app:app).action
            }
            return blockedReason(target,mapping:mapping,device:device) == nil
        })
    }
    func blockedReason(_ g: Gesture, mapping: Mapping, device: String) -> String? {
        if !enabled { return "Engine disabled" }
        if !mapping.enabled || mapping.action.kind == .none { return "No action" }
        if mapping.action.kind == .native { return "Native gesture: observing only" }
        if mapping.action.kind == .notificationCenter { return "Notification Center: assign your configured keyboard shortcut instead" }
        if !safety.nativeConflictsResolved { return "Complete native gesture conflict setup" }
        if g.fingers == 4 && [.left, .right].contains(g.direction) && !safety.nativeHorizontalDisabled { return "Disable native desktop swipes before reassigning them" }
        if g.direction == .tap && !safety.tapConflictsResolved { return "Complete tap conflict setup first" }
        return nil
    }
    func validated() throws -> Configuration {
        func require(_ b: Bool, _ message: String) throws { if !b { throw ConfigError.invalid(message) } }
        try require(schemaVersion == 2, "Unsupported configuration version")
        func validate(_ s: Sensitivity) throws {
            try require([s.horizontalMM, s.verticalMM].allSatisfy { $0.isFinite && (0.5...20).contains($0) }, "Distance must be 0.5–20 mm")
            try require((0.05...1.5).contains(s.tapDuration) && (0.1...10).contains(s.tapToleranceMM) && (0.1...10).contains(s.activationMM) && (1.05...4).contains(s.diagonalRatio) && (0...0.5).contains(s.jitterMM) && (0.1...20).contains(s.volumePercent), "Invalid sensitivity")
            try s.effectiveTapOptions.validate(); try s.effectiveClickOptions.validate()
        }
        func validateShortcut(_ s: Shortcut) throws {
            try require(s.keyCode <= 127 && s.modifiers.allSatisfy { ["command", "option", "shift", "control", "fn"].contains($0) } && (0...2).contains(s.delay), "Invalid keyboard shortcut")
        }
        try require((Array((rowEnabled ?? [:]).keys) + profiles.flatMap { Array(($0.rowEnabled ?? [:]).keys) }).allSatisfy { ["3","4"].contains($0) }, "Invalid finger row")
        try validate(sensitivity)
        try require(Set(profiles.map(\.bundleID)).count == profiles.count, "Duplicate app profiles")
        for p in profiles { if let s = p.sensitivity { try validate(s) } }
        for c in calibrations.values { try require(c.widthMM.isFinite && c.heightMM.isFinite && (!c.confirmed || c.valid), "Invalid calibration") }
        for (id, m) in Array(mappings) + profiles.flatMap({ Array($0.mappings) }) {
            try m.tapOptions?.validate(); try m.clickOptions?.validate()
            try require(Gesture.all.contains { $0.id == id }, "Unknown gesture \(id)")
            try require(m.distanceMM == nil || (0.5...20).contains(m.distanceMM!), "Invalid mapping distance")
            try require((0...5).contains(m.cooldown), "Invalid cooldown")
            try require(m.action.shortcuts.count <= 32, "Too many shortcuts")
            if [.shortcut,.sequence,.applicationShortcut].contains(m.action.kind) { try require(!m.action.shortcuts.isEmpty, "Choose at least one shortcut") }
            if let v = m.action.volumePercent { try require((0.1...20).contains(v), "Invalid volume step") }
            for s in m.action.shortcuts { try validateShortcut(s) }
        }
        for s in systemShortcuts.values { try validateShortcut(s) }
        return self
    }
}
enum ConfigError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil }
}
