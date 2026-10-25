import Foundation

/// One contiguous, ruler-measured, single-finger stroke. Separate from recognition.
struct CalibrationTrial {
    let horizontal: Bool
    private var origin: Contact?
    private(set) var travel = 0.0
    private(set) var crossAxis = 0.0
    private(set) var ended = false
    private(set) var invalid = false
    init(horizontal: Bool) { self.horizontal = horizontal }
    mutating func observe(_ contacts: [Contact]) {
        guard !ended, !invalid else { return }
        if contacts.isEmpty { if origin != nil { ended = true }; return }
        guard contacts.count == 1, let contact = contacts.first,
              contact.x.isFinite, contact.y.isFinite, (0...1).contains(contact.x), (0...1).contains(contact.y) else { invalid = true; return }
        if origin == nil { origin = contact }
        guard let origin, origin.id == contact.id else { invalid = true; return }
        travel = max(travel, abs(horizontal ? contact.x-origin.x : contact.y-origin.y))
        crossAxis = max(crossAxis, abs(horizontal ? contact.y-origin.y : contact.x-origin.x))
    }
    func fullAxisMM(measuredDistance: Double) throws -> Double {
        guard ended, !invalid, travel >= 0.03, crossAxis < travel*0.3, (5...100).contains(measuredDistance) else {
            throw ConfigError.invalid("Use one uninterrupted finger stroke along one axis for a measured 5–100 mm, then lift. Keep cross-axis movement small.")
        }
        let full = measuredDistance/travel
        guard (20...300).contains(full) else { throw ConfigError.invalid("Measurement implies an implausible trackpad size; try again") }
        return full
    }
}
