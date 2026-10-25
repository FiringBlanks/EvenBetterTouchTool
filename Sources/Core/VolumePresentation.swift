import Foundation

struct VolumeLevel: Equatable {
    var value: Double
    var muted: Bool
    var percent: Int { Int((min(1,max(0,value))*100).rounded()) }
}
struct VolumePresentation {
    private(set) var level = VolumeLevel(value:0,muted:false)
    private(set) var deadline = -Double.infinity
    mutating func update(_ level: VolumeLevel, time: Double) {
        guard level.value.isFinite, time.isFinite else { return }
        self.level = level; deadline = time+2
    }
    func visible(at time: Double) -> Bool { time < deadline }
}
