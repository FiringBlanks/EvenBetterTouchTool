import Foundation

enum SystemShortcutChoice: Equatable {
    case configured(Shortcut), disabled, unavailable
    static func read(_ entry: [String:Any]?) -> SystemShortcutChoice {
        guard let entry else { return .unavailable }
        if entry["enabled"] as? Bool == false { return .disabled }
        guard entry["enabled"] as? Bool == true, let value = entry["value"] as? [String:Any],
              value["type"] as? String == "standard", let p = value["parameters"] as? [NSNumber], p.count == 3,
              p[1].doubleValue.isFinite, p[1].doubleValue.rounded() == p[1].doubleValue, (0...127).contains(p[1].intValue),
              p[2].doubleValue.isFinite, p[2].doubleValue >= 0 else { return .unavailable }
        let flags = p[2].uint64Value
        let modifiers: [(String,UInt64)] = [("command",1<<20),("shift",1<<17),("control",1<<18),("option",1<<19),("fn",1<<23)]
        return .configured(Shortcut(keyCode:p[1].uint16Value,modifiers:modifiers.filter { flags & $0.1 != 0 }.map { $0.0 }))
    }
    func shortcut(fallback: Shortcut?) -> Shortcut? {
        switch self { case .configured(let value): return value; case .disabled: return nil; case .unavailable: return fallback }
    }
}
