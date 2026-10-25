import Foundation

struct Contact: Equatable { var id: Int; var x: Double; var y: Double }
struct TouchFrame {
    var time: Double
    var contacts: [Contact]
    var physicalButton = false
}
struct GestureTrigger {
    var gesture: Gesture
    var mapping: Mapping
    var count: Int
}
struct EngineSnapshot {
    var fingers = 0
    var contacts: [Contact] = []
    var dxMM = 0.0
    var dyMM = 0.0
    var gesture = "Waiting for fingers"
    var reason = ""
}
/// Pure, synchronous state machine. The driver owns it on a serial queue.
/// No timers, momentum, system calls, or pending action queue live here.
final class GestureEngine {
    var config: Configuration
    var app: String
    var device: String
    private(set) var snapshot = EngineSnapshot()
    private var start: [Contact] = []
    private var lastX = 0.0, lastY = 0.0, originX = 0.0, originY = 0.0
    private var startTime = 0.0, lastTime = -Double.infinity
    private var releasingAt: Double?
    private var cancelled = false, clicked = false, swiped = false, singleFired = false
    private var axis: Bool? // true = horizontal
    private var remainder = 0.0, lastSign = 0.0
    private var maxMovement = 0.0
    private var lastFire = -Double.infinity
    var trackedFingerCount: Int { cancelled ? 0 : start.count }
    init(config: Configuration, app: String, device: String) { self.config = config; self.app = app; self.device = device }
    func cancel(_ reason: String = "Cancelled; lift all fingers") { cancelled = true; remainder = 0; snapshot.reason = reason }
    func reset() {
        start = []; releasingAt = nil; cancelled = false; clicked = false; swiped = false; singleFired = false
        axis = nil; remainder = 0; lastSign = 0; maxMovement = 0; lastFire = -.infinity; lastTime = -.infinity
    }
    func physicalClick() { clicked = true; cancel("Physical button observed; tap cancelled") }
    func process(_ frame: TouchFrame) -> [GestureTrigger] {
        snapshot.fingers = frame.contacts.count; snapshot.contacts = frame.contacts
        guard frame.time.isFinite && frame.time > lastTime else { return [] }
        if frame.time - lastTime > 0.35 && !start.isEmpty { cancel("Contact stream interrupted") }
        lastTime = frame.time
        if frame.physicalButton { physicalClick() }
        let c = frame.contacts
        guard c.count <= 16, Set(c.map(\.id)).count == c.count, c.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { cancel("Invalid contact frame"); return [] }
        let sensitivity = config.sensitivity(for: app)
        let scale = config.movementScale(for: device)
        if c.isEmpty {
            defer { reset() }
            guard !start.isEmpty, !cancelled, !clicked, !swiped, frame.time - startTime <= sensitivity.tapDuration,
                  maxMovement <= sensitivity.tapToleranceMM, releasingAt == nil || frame.time - releasingAt! <= 0.08 else { return [] }
            let g = Gesture(fingers: start.count, direction: .tap), m = config.mapping(Gesture(fingers: start.count, direction: .tap), app: app)
            snapshot.gesture = g.title
            if let reason = config.blockedReason(g, mapping: m, device: device) { snapshot.reason = reason; return [] }
            return [GestureTrigger(gesture: g, mapping: m, count: 1)]
        }
        if cancelled { return [] }
        guard c.count == 3 || c.count == 4 else {
            if !start.isEmpty { if releasingAt == nil { releasingAt = frame.time }; if frame.time - releasingAt! > 0.08 { cancel("Finger count changed") } }
            return []
        }
        if start.isEmpty {
            start = c; startTime = frame.time
            originX = c.map(\.x).reduce(0,+) / Double(c.count); originY = c.map(\.y).reduce(0,+) / Double(c.count)
            lastX = originX; lastY = originY
            snapshot.dxMM = 0; snapshot.dyMM = 0; snapshot.reason = ""; snapshot.gesture = "Tracking \(c.count) fingers"
            return []
        }
        // A short settling window permits fingers landing a few milliseconds apart.
        if c.count != start.count && frame.time - startTime < 0.04 && !swiped {
            start = c
            originX = c.map(\.x).reduce(0,+) / Double(c.count); originY = c.map(\.y).reduce(0,+) / Double(c.count)
            lastX = originX; lastY = originY; maxMovement = 0
            return []
        }
        if c.count < start.count {
            guard c.allSatisfy({ f in start.contains { $0.id == f.id } }) else { cancel("Finger identity changed during release"); return [] }
            if releasingAt == nil { releasingAt = frame.time }
            if frame.time-releasingAt! > 0.08 { cancel("Finger count changed") }
            return []
        }
        guard releasingAt == nil, c.count == start.count, Set(c.map(\.id)) == Set(start.map(\.id)) else { cancel("Finger identity/count changed"); return [] }
        let x = c.map(\.x).reduce(0,+) / Double(c.count), y = c.map(\.y).reduce(0,+) / Double(c.count)
        guard abs(x - lastX) <= 0.2, abs(y - lastY) <= 0.2 else { cancel("Implausible coordinate jump"); return [] }
        for finger in c {
            if let origin = start.first(where: { $0.id == finger.id }) {
                maxMovement = max(maxMovement, hypot((finger.x-origin.x)*scale.width, (finger.y-origin.y)*scale.height))
            }
        }
        let totalX = (x-originX)*scale.width, totalY = (y-originY)*scale.height
        snapshot.dxMM = totalX; snapshot.dyMM = totalY
        if hypot(totalX, totalY) >= sensitivity.activationMM || maxMovement > sensitivity.tapToleranceMM+1e-7 { swiped = true }
        guard frame.time - startTime >= 0.04 else { return [] }
        if axis == nil {
            let ax = abs(totalX), ay = abs(totalY)
            guard max(ax,ay)+1e-7 >= sensitivity.activationMM else { return [] }
            if ax >= ay*sensitivity.diagonalRatio { axis = true }
            else if ay >= ax*sensitivity.diagonalRatio { axis = false }
            else { snapshot.reason = "Diagonal movement rejected"; return [] }
        }
        let horizontal = axis!
        let movement = horizontal ? (x-lastX)*scale.width : (y-lastY)*scale.height
        guard abs(movement)+1e-7 >= sensitivity.jitterMM, abs(movement) > 1e-9 else { return [] }
        lastX = x; lastY = y
        let sign = movement > 0 ? 1.0 : -1.0
        // Fractional credit belongs to its direction. Reversal starts from the
        // turning point, so it never pays off distance travelled the other way.
        if sign != lastSign { remainder = 0; lastSign = sign }
        remainder += abs(movement)
        let physicalDirection: Direction = horizontal ? (sign > 0 ? .right : .left) : (sign > 0 ? .up : .down)
        var g = Gesture(fingers: c.count, direction: physicalDirection)
        let original = config.mapping(g, app: app)
        if original.reverse {
            g.direction = horizontal ? (sign > 0 ? .left : .right) : (sign > 0 ? .down : .up)
        }
        var m = original
        if original.reverse { m.action = config.mapping(g, app: app).action }
        snapshot.gesture = g.title
        if let reason = config.blockedReason(g, mapping: m, device: device) { snapshot.reason = reason; remainder = 0; return [] }
        let distance = m.distanceMM ?? (horizontal ? sensitivity.horizontalMM : sensitivity.verticalMM)
        guard remainder + 1e-7 >= distance else { return [] }
        let continuous = m.continuous && m.action.supportsContinuous
        if !continuous && singleFired { remainder = 0; return [] }
        let count = continuous ? Int(floor((remainder + 1e-7)/distance)) : 1
        remainder = continuous ? max(0, remainder-Double(count)*distance) : 0
        guard count <= 64 else { cancel("Movement burst too large; lift fingers"); return [] }
        guard frame.time-lastFire >= m.cooldown else { return [] }
        lastFire = frame.time; singleFired = true; snapshot.reason = ""
        return [GestureTrigger(gesture: g, mapping: m, count: count)]
    }
}

enum ActionCommand: Equatable {
    case shortcut(Shortcut), media(Int), volume(Double), mute, mouse(Int), open(String, Bool), system(ActionKind)
}
enum ActionPlanner {
    static func commands(_ action: Action, app: String, sensitivity: Sensitivity) -> [ActionCommand] {
        switch action.kind {
        case .none, .native, .notificationCenter: return []
        case .previousTab, .nextTab:
            let previous = action.kind == .previousTab
            if app == "com.google.Chrome" { return [.shortcut(Shortcut(keyCode: previous ? 123 : 124, modifiers: ["command", "option"]))] }
            return [.shortcut(Shortcut(keyCode: 48, modifiers: previous ? ["control", "shift"] : ["control"]))]
        case .playPause: return [.media(16)]
        case .nextTrack: return [.media(17)]
        case .previousTrack: return [.media(18)]
        case .volumeUp, .volumeDown: return [.volume((action.kind == .volumeUp ? 1 : -1) * (action.volumePercent ?? sensitivity.volumePercent) / 100)]
        case .mute: return [.mute]
        case .browserBack, .browserForward: return [.shortcut(Shortcut(keyCode: action.kind == .browserBack ? 33 : 30, modifiers: ["command"]))]
        case .previousApplication, .nextApplication: return [.shortcut(Shortcut(keyCode: 48, modifiers: action.kind == .previousApplication ? ["command"] : ["command", "shift"]))]
        case .lockScreen: return [.shortcut(Shortcut(keyCode: 12, modifiers: ["command", "control"]))]
        case .screenshot: return [.shortcut(Shortcut(keyCode: 23, modifiers: ["command", "shift"]))]
        case .leftClick: return [.mouse(0)]
        case .rightClick: return [.mouse(1)]
        case .middleClick: return [.mouse(2)]
        case .shortcut: return action.shortcuts.first.map { [.shortcut($0)] } ?? []
        case .sequence: return action.shortcuts.map { .shortcut($0) }
        case .applicationShortcut: return app == action.bundleID ? action.shortcuts.map { .shortcut($0) } : []
        case .openApplication: return [.open(action.bundleID, false)]
        case .activateApplication: return [.open(action.bundleID, true)]
        default: return [.system(action.kind)]
        }
    }
    static func volume(_ current: Float, delta: Double) -> Float { min(1, max(0, current + Float(delta))) }
    static func mediaData(key: Int, down: Bool) -> Int { (key << 16) | ((down ? 0xA : 0xB) << 8) }
}
