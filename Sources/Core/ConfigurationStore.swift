import Foundation

final class ConfigurationStore {
    let url: URL
    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/threefinger.json")) { self.url = url }
    func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { let c = Configuration.defaults; try save(c); return c }
        let data = try Data(contentsOf: url)
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["schemaVersion"] == nil {
            let legacy = try JSONDecoder().decode(Legacy.self, from: data)
            let backup = url.deletingLastPathComponent().appendingPathComponent("threefinger.legacy-\(UUID().uuidString).json")
            try data.write(to: backup, options: .atomic)
            var c = Configuration.defaults
            // Preserve explicit legacy sequences globally. Legacy normalized thresholds
            // cannot be converted to mm before calibration; retain them in the backup.
            for m in legacy.manipulators {
                guard let direction = Direction(rawValue: m.from.gesture.replacingOccurrences(of: "three_finger_swipe_", with: "")), direction.isSwipe else { continue }
                let seq = try m.to.map { t -> Shortcut in
                    guard let key = KeyCodes.values[t.key_code] else { throw ConfigError.invalid("Unknown legacy key \(t.key_code); original file preserved") }
                    return Shortcut(keyCode: key, modifiers: (t.modifiers ?? []).map { $0.replacingOccurrences(of: "left_", with: "").replacingOccurrences(of: "right_", with: "") })
                }
                c.mappings[Gesture(fingers: 3, direction: direction).id] = Mapping(action: Action(kind: .sequence, shortcuts: seq))
                // Preserve the old user's intent instead of masking it with new app defaults.
                for i in c.profiles.indices { c.profiles[i].mappings.removeValue(forKey: Gesture(fingers: 3, direction: direction).id) }
            }
            try save(c)
            return c
        }
        return try JSONDecoder().decode(Configuration.self, from: data).validated()
    }
    func save(_ config: Configuration) throws {
        _ = try config.validated()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
    func importFile(_ source: URL) throws -> Configuration {
        var c = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: source)).validated()
        c.safety = Safety(); c.calibrations = [:]; c.selectedDevice = ""
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.copyItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent("threefinger.pre-import-\(UUID().uuidString).json"))
        }
        try save(c); return c
    }
    private struct Legacy: Decodable {
        var manipulators: [Manipulator]
        struct Manipulator: Decodable { var from: From; var to: [To] }
        struct From: Decodable { var gesture: String }
        struct To: Decodable { var key_code: String; var modifiers: [String]? }
    }
}
enum KeyCodes {
    static let values: [String: UInt16] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"close_bracket":30,"o":31,"u":32,"open_bracket":33,"i":34,"p":35,"return_or_enter":36,"l":37,"j":38,"k":40,"n":45,"m":46,"tab":48,"spacebar":49,"delete_or_backspace":51,"escape":53,"left_arrow":123,"right_arrow":124,"down_arrow":125,"up_arrow":126,"f1":122,"f2":120,"f3":99,"f4":118,"f5":96,"f6":97,"f7":98,"f8":100,"f9":101,"f10":109,"f11":103,"f12":111,"home":115,"page_up":116,"end":119,"page_down":121]
}
