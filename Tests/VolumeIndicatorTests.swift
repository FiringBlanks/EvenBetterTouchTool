import AppKit

@main struct VolumeIndicatorTests {
    static var passed = 0, failed = 0
    static func pump(_ seconds: Double) { RunLoop.current.run(until:Date().addingTimeInterval(seconds)) }
    static func expect(_ condition: @autoclosure () -> Bool) throws {
        if !condition() { throw NSError(domain:"VolumeIndicatorTests",code:1,userInfo:[NSLocalizedDescriptionKey:"Expectation failed"]) }
    }
    static func test(_ name: String, _ body: (VolumeIndicator, NSStatusItem) throws -> Void) {
        let item = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        let indicator = VolumeIndicator()
        defer { indicator.hide(); NSStatusBar.system.removeStatusItem(item) }
        do { try body(indicator,item); passed += 1; print("PASS \(name)") }
        catch { failed += 1; print("FAIL \(name): \(error)") }
    }
    static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching(); pump(0.05)
        test("Live volume updates keep their first frame despite status item layout changes") { indicator,item in
            var visibility = [Bool]()
            indicator.onVisibilityChanged = { visible in item.length = visible ? VolumeIndicator.statusWidth : NSStatusItem.squareLength; visibility.append(visible) }
            indicator.show(VolumeLevel(value:0.09,muted:false),anchoredTo:item.button); pump(0.05)
            guard let first = indicator.frame else { throw NSError(domain:"VolumeIndicatorTests",code:2,userInfo:[NSLocalizedDescriptionKey:"A normal macOS graphics session is required"]) }
            indicator.show(VolumeLevel(value:0.99,muted:false),anchoredTo:item.button); pump(0.05)
            try expect(indicator.frame == first)
            indicator.show(VolumeLevel(value:1,muted:false),anchoredTo:item.button); pump(0.05)
            try expect(indicator.frame == first && visibility == [true] && item.length == VolumeIndicator.statusWidth)
        }
        test("Interaction begins a fade and closes the panel") { indicator,item in
            indicator.show(VolumeLevel(value:0.42,muted:false),anchoredTo:item.button)
            indicator.dismissForInteraction(); try expect(indicator.fading)
            pump(0.35); try expect(indicator.frame == nil)
        }
        test("A new volume update cancels an old fade without moving or hiding the panel") { indicator,item in
            indicator.show(VolumeLevel(value:0.42,muted:false),anchoredTo:item.button)
            let first = indicator.frame
            indicator.dismissForInteraction(); indicator.show(VolumeLevel(value:0.44,muted:false),anchoredTo:item.button)
            try expect(!indicator.fading); pump(0.35)
            try expect(first != nil && indicator.frame == first)
        }
        test("Idle feedback closes after its two-second deadline and fade") { indicator,item in
            indicator.show(VolumeLevel(value:0.42,muted:false),anchoredTo:item.button)
            pump(2.4); try expect(indicator.frame == nil)
        }
        print("\n\(passed) indicator tests passed; \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
