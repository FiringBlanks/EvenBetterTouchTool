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
        test("Small pointer drift stays visible; deliberate displacement begins a fade") { indicator,item in
            let origin=NSEvent.mouseLocation
            indicator.show(VolumeLevel(value:0.42,muted:false),anchoredTo:item.button)
            for _ in 0..<20 { indicator.pointerMoved(to:NSPoint(x:origin.x+8,y:origin.y-4)); indicator.pointerMoved(to:origin) }
            try expect(!indicator.fading && indicator.frame != nil)
            indicator.pointerMoved(to:NSPoint(x:origin.x+23,y:origin.y)); try expect(!indicator.fading)
            indicator.pointerMoved(to:NSPoint(x:origin.x+24,y:origin.y)); try expect(indicator.fading)
            pump(0.35); try expect(indicator.frame == nil)
        }
        test("A new volume update cancels an old fade without moving or hiding the panel") { indicator,item in
            let origin=NSEvent.mouseLocation
            indicator.show(VolumeLevel(value:0.42,muted:false),anchoredTo:item.button)
            let first = indicator.frame
            indicator.pointerMoved(to:NSPoint(x:origin.x+30,y:origin.y)); indicator.show(VolumeLevel(value:0.44,muted:false),anchoredTo:item.button)
            try expect(!indicator.fading); pump(0.35)
            try expect(first != nil && indicator.frame == first)
        }
        test("Idle feedback closes after its two-second deadline and fade") { indicator,item in
            indicator.show(VolumeLevel(value:0.42,muted:false),anchoredTo:item.button)
            pump(2.4); try expect(indicator.frame == nil)
        }
        test("Clicks, typing, and scrolling do not initiate an early fade") { indicator,item in
            indicator.show(VolumeLevel(value:0.42,muted:false),anchoredTo:item.button)
            let click=NSEvent.mouseEvent(with:.leftMouseDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            let key=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"x",charactersIgnoringModifiers:"x",isARepeat:false,keyCode:7)!
            let scroll=NSEvent(cgEvent:CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:20,wheel2:0,wheel3:0)!)!
            for event in [click,key,scroll] { indicator.handleEvent(event) }
            try expect(!indicator.fading && indicator.frame != nil)
        }
        print("\n\(passed) indicator tests passed; \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
