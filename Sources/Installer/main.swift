import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let manager = LauncherManager()
guard arguments.count >= 2 else { fputs("Usage: launcher-tool create|remove|status APP SHORTCUT...; launcher-tool resolve APP\n", stderr); exit(2) }
let app = URL(fileURLWithPath: arguments[1])
let locations = arguments.dropFirst(2).map { URL(fileURLWithPath: $0) }
do {
    switch arguments[0] {
    case "create":
        guard !locations.isEmpty else { exit(2) }
        print(try manager.create(app: app, locations: locations).path)
    case "remove":
        for url in try manager.remove(app: app, locations: locations) { print("Removed shortcut: \(url.path)") }
    case "status":
        guard locations.count == 1 else { exit(2) }
        print(manager.state(app: app, shortcut: locations[0]).rawValue)
    case "resolve": print(try manager.resolveApplication(app).path)
    default: exit(2)
    }
} catch { fputs(error.localizedDescription+"\n", stderr); exit(1) }
