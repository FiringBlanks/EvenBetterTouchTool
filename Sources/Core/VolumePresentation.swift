import Foundation

struct VolumeLevel: Equatable {
    var value: Double
    var muted: Bool
    var percent: Int { Int((min(1,max(0,value))*100).rounded()) }
}
struct VolumePresentation {
    enum Phase { case hidden, visible, fading }
    private(set) var level = VolumeLevel(value:0,muted:false)
    private(set) var deadline = -Double.infinity
    private(set) var phase = Phase.hidden
    mutating func update(_ level: VolumeLevel, time: Double) {
        guard level.value.isFinite, time.isFinite else { return }
        self.level = level; deadline = time+2; phase = .visible
    }
    func visible(at time: Double) -> Bool { phase != .hidden && time < deadline }
    @discardableResult mutating func beginFade() -> Bool {
        guard phase == .visible else { return false }
        phase = .fading; return true
    }
    mutating func hide() { phase = .hidden; deadline = -.infinity }
}
