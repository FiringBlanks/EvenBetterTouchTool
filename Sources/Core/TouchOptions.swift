import Foundation

struct TapOptions: Codable, Equatable {
    var duration = 0.50
    var movement = 2.0
    var swipeCancellation = 1.5
    var landingWindow = 0.15
    var releaseWindow = 0.20
    var cooldown = 0.25
    var clickDelay = 0.08
    var clickExclusion = 0.12
    func validate() throws {
        guard (0.05...1.5).contains(duration), (0.1...10).contains(movement), (0.1...10).contains(swipeCancellation), (0...0.4).contains(landingWindow),
              (0.02...0.5).contains(releaseWindow), (0...2).contains(cooldown), (0...0.25).contains(clickDelay),
              (0.02...0.5).contains(clickExclusion) else { throw ConfigError.invalid("Invalid tap settings") }
    }
}
struct ClickOptions: Codable, Equatable {
    var button = 0
    var contactAge = 0.15
    var settleTime = 0.015
    var landingWindow = 0.10
    var maxDuration = 2.0
    var movement = 2.5
    var cooldown = 0.35
    var ignoreSynthetic = true
    func validate() throws {
        guard (0...2).contains(button), (0.02...0.5).contains(contactAge), (0...0.3).contains(settleTime), (0...0.3).contains(landingWindow),
              (0.1...10).contains(maxDuration), (0.1...20).contains(movement), (0...3).contains(cooldown)
        else { throw ConfigError.invalid("Invalid physical press settings") }
    }
}

/// An observed mouse press while three/four fresh contacts rest on the selected
/// trackpad. The original mouse events pass through. Quartz does not identify
/// their originating device, so another mouse can also satisfy this association.
struct PressRecognizer {
    private struct Pending {
        var fingers: Int
        var contacts: [Contact]
        var at: Double
        var options: ClickOptions
        var movement = 0.0
    }
    private var contacts: [Contact] = []
    private var lastFrame = -Double.infinity
    private var lastContact = -Double.infinity
    private var settledAt = -Double.infinity
    private var heldButton: Int?
    private var pending: Pending?
    private var downAt: Double?
    private var downOptions: ClickOptions?
    private var lastFire: [Int:Double] = [:]
    var fingers: Int { pending?.fingers ?? contacts.count }
    mutating func reset() { self = PressRecognizer() }
    mutating func observe(_ contacts: [Contact], time: Double, scale: MovementScale) {
        guard time.isFinite, contacts.count <= 4, Set(contacts.map(\.id)).count == contacts.count,
              contacts.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { reset(); return }
        if time-lastFrame > 0.35 { pending = nil; settledAt = time }
        if Set(contacts.map(\.id)) != Set(self.contacts.map(\.id)) { settledAt = time }
        self.contacts = contacts; lastFrame = time
        if !contacts.isEmpty { lastContact = time }
        if heldButton != nil, pending == nil, let downAt, let options = downOptions,
           time-downAt <= options.landingWindow, time-settledAt >= options.settleTime, (3...4).contains(contacts.count) {
            pending = Pending(fingers:contacts.count,contacts:contacts,at:downAt,options:options)
        }
        if var press = pending {
            if contacts.count > press.fingers, time-press.at <= press.options.landingWindow {
                press = Pending(fingers:contacts.count,contacts:contacts,at:press.at,options:press.options)
            }
            for contact in contacts {
                guard let origin = press.contacts.first(where: { $0.id == contact.id }) else { pending = nil; downOptions = nil; return }
                press.movement = max(press.movement,hypot((contact.x-origin.x)*scale.width,(contact.y-origin.y)*scale.height))
            }
            pending = press
        }
    }
    mutating func button(_ button: Int, down: Bool, time: Double, options: ClickOptions) -> Int? {
        guard time.isFinite else { return nil }
        if down {
            if heldButton != nil { if heldButton != button { pending = nil }; return nil }
            guard button == options.button else { return nil }
            heldButton = button
            downAt = time; downOptions = options
            guard (3...4).contains(contacts.count), time-lastFrame <= options.contactAge,
                  time-settledAt >= options.settleTime else { return nil }
            pending = Pending(fingers:contacts.count,contacts:contacts,at:time,options:options)
            return nil
        }
        guard heldButton == button else { return nil }
        heldButton = nil
        downAt = nil; downOptions = nil
        guard let press = pending else { return nil }
        pending = nil
        guard time >= press.at, time-press.at <= press.options.maxDuration,
              time-lastContact <= press.options.contactAge, press.movement <= press.options.movement,
              time-(lastFire[press.fingers] ?? -.infinity) >= max(options.cooldown,press.options.cooldown) else { return nil }
        lastFire[press.fingers] = time
        return press.fingers
    }
}
