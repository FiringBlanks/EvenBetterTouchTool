import Foundation

struct KeyboardStroke: Equatable {
    var key: UInt16
    var down: Bool
    var modifiers: [String]
    var navigation = false
    var function = false
}
enum KeyboardPlan {
    /// Real modifier edges plus the Fn/NumericPad flags of Apple arrow keys are
    /// needed by system hotkeys; flagging an arrow alone can be ignored by Dock.
    static func strokes(_ shortcut: Shortcut, held: Set<String> = []) -> [KeyboardStroke] {
        let modifiers: [(String,UInt16)] = [("control",59),("option",58),("shift",56),("command",55),("fn",63)]
        let navigation = [UInt16(123),124,125,126,115,119,116,121,117].contains(shortcut.keyCode)
        let function = [UInt16(122),120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90].contains(shortcut.keyCode)
        var result = [KeyboardStroke](), flags = held, pressed = [(String,UInt16)]()
        for (name,key) in modifiers where shortcut.modifiers.contains(name) && !held.contains(name) {
            flags.insert(name); pressed.append((name,key))
            result.append(KeyboardStroke(key:key,down:true,modifiers:flags.sorted()))
        }
        for down in [true,false] { result.append(KeyboardStroke(key:shortcut.keyCode,down:down,modifiers:flags.sorted(),navigation:navigation,function:function)) }
        for (name,key) in pressed.reversed() {
            flags.remove(name); result.append(KeyboardStroke(key:key,down:false,modifiers:flags.sorted()))
        }
        return result
    }
}
