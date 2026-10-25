import Foundation

/// Correlates continuous scroll events with the selected trackpad's fresh contact
/// stream. It cannot intercept WindowServer's private Mission Control gestures.
struct ScrollFilter {
    private var custom = Set<Gesture>()
    private var fingers = 0
    private var previous: (Double, Double)?
    private var axis: Bool?
    private var direction: Direction?
    private var lastFrame = -Double.infinity
    private var lastBlocked = -Double.infinity
    private var blockedStream = false
    mutating func configure(custom: Set<Gesture>) { self = ScrollFilter(); self.custom = custom }
    mutating func observe(contacts: [Contact], trackedFingers: Int, time: Double) {
        guard time.isFinite else { return }
        if trackedFingers != fingers {
            previous = nil; axis = nil; direction = nil
            if trackedFingers > 0 { blockedStream = false }
        }
        fingers = trackedFingers; lastFrame = time
        guard (3...4).contains(fingers), contacts.count == fingers else { return }
        let x = contacts.reduce(0) { $0+$1.x } / Double(fingers)
        let y = contacts.reduce(0) { $0+$1.y } / Double(fingers)
        defer { previous = (x,y) }
        guard let previous else { return }
        let dx = x-previous.0, dy = y-previous.1
        guard max(abs(dx),abs(dy)) > 0.00001 else { return }
        if axis == nil {
            if abs(dx) > abs(dy)*1.35 { axis = true }
            else if abs(dy) > abs(dx)*1.35 { axis = false }
        }
        if let horizontal = axis {
            let delta = horizontal ? dx : dy
            if abs(delta) > 0.00001 { direction = horizontal ? (delta > 0 ? .right : .left) : (delta > 0 ? .up : .down) }
        }
    }
    mutating func suppress(time: Double, continuous: Bool, synthetic: Bool, dx: Double, dy: Double, phase: Int64, momentum: Int64) -> Bool {
        guard continuous, !synthetic, !custom.isEmpty, time.isFinite else { return false }
        if momentum != 0 {
            let block = blockedStream && time-lastBlocked < 0.5
            if block { lastBlocked = time }
            if momentum == 3 { blockedStream = false }
            return block
        }
        guard (3...4).contains(fingers), time-lastFrame < 0.12 else {
            // A gesture's end event can arrive just after the last contact frame.
            if fingers == 0, phase & (4|8) != 0, blockedStream, time-lastBlocked < 0.2 { return true }
            if phase & 1 != 0 { blockedStream = false }
            return false
        }
        let horizontal = abs(dx) > abs(dy)
        let candidates: [Direction] = horizontal ? [.left,.right] : [.up,.down]
        let block: Bool
        if let direction, candidates.contains(direction) {
            block = custom.contains(Gesture(fingers:fingers,direction:direction))
        } else {
            // Before movement resolves, suppress only an entirely custom axis.
            // A mixed native/custom axis passes until raw direction is known.
            block = candidates.allSatisfy { custom.contains(Gesture(fingers:fingers,direction:$0)) }
        }
        blockedStream = block
        if block { lastBlocked = time }
        return block
    }
}
