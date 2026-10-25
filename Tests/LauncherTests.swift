import Foundation

@main struct LauncherTests {
    static var passed = 0, failed = 0
    struct Fixture {
        let root: URL, app: URL, applications: URL, desktop: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("EBTT-launcher-tests-"+UUID().uuidString)
            app = root.appendingPathComponent("Installed Apps/EvenBetterTouchTool.app")
            applications = root.appendingPathComponent("Applications/EvenBetterTouchTool.app")
            desktop = root.appendingPathComponent("Desktop/EvenBetterTouchTool.app")
            try Self.makeApp(app)
            try FileManager.default.createDirectory(at: applications.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: desktop.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        static func makeApp(_ url: URL, id: String = LauncherManager.bundleID) throws {
            try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": "EvenBetterTouchTool", "CFBundleExecutable": "EvenBetterTouchTool", "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
            try Data("test executable".utf8).write(to: url.appendingPathComponent("Contents/MacOS/EvenBetterTouchTool"))
        }
    }
    static func expect(_ b: @autoclosure () throws -> Bool) throws { if try !b() { throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expectation failed"]) } }
    static func test(_ name: String, _ body: (Fixture, LauncherManager) throws -> Void) {
        var fixture: Fixture?
        defer { if let fixture { try? FileManager.default.removeItem(at: fixture.root) } }
        do { let f = try Fixture(); fixture = f; try body(f, LauncherManager()); passed += 1; print("PASS \(name)") }
        catch { failed += 1; print("FAIL \(name): \(error.localizedDescription)") }
    }
    static func main() throws {
        test("Fresh install creates a native Finder alias") { f, manager in
            let result = try manager.create(app: f.app, locations: [f.applications, f.desktop])
            try expect(result == f.applications)
            try expect(try f.applications.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile == true)
            try expect(try manager.resolveApplication(f.applications) == f.app.standardizedFileURL)
        }
        test("Repeated install keeps the existing alias intact") { f, manager in
            try manager.create(app: f.app, locations: [f.applications])
            let before = try Data(contentsOf: f.applications)
            try manager.create(app: f.app, locations: [f.applications, f.desktop])
            try expect(try Data(contentsOf: f.applications) == before)
            try expect(!FileManager.default.fileExists(atPath: f.desktop.path))
        }
        test("Updating the app at the same path preserves launchability") { f, manager in
            try manager.create(app: f.app, locations: [f.applications])
            try FileManager.default.removeItem(at: f.app); try Fixture.makeApp(f.app)
            try manager.create(app: f.app, locations: [f.applications, f.desktop])
            try expect(try manager.resolveApplication(f.applications) == f.app.standardizedFileURL)
        }
        test("Desktop fallback preserves an unrelated Applications item") { f, manager in
            let sentinel = Data("leave me alone".utf8); try sentinel.write(to: f.applications)
            let result = try manager.create(app: f.app, locations: [f.applications, f.desktop])
            try expect(result == f.desktop && manager.state(app: f.app, shortcut: f.desktop) == .managed)
            try expect(try Data(contentsOf: f.applications) == sentinel)
        }
        test("Unavailable Applications folder falls back without making a new shared folder") { f, manager in
            let missing = f.root.appendingPathComponent("Unavailable/EvenBetterTouchTool.app")
            try expect(try manager.create(app: f.app, locations: [missing, f.desktop]) == f.desktop)
            try expect(!FileManager.default.fileExists(atPath: missing.deletingLastPathComponent().path))
        }
        test("An unrelated app is never overwritten by a launcher") { f, manager in
            try Fixture.makeApp(f.applications, id: "org.example.unrelated")
            try expect(try manager.create(app: f.app, locations: [f.applications, f.desktop]) == f.desktop)
            try expect(Bundle(url: f.applications)?.bundleIdentifier == "org.example.unrelated")
        }
        test("No available location fails without replacing existing files") { f, manager in
            try Data("one".utf8).write(to: f.applications); try Data("two".utf8).write(to: f.desktop)
            var rejected = false
            do { try manager.create(app: f.app, locations: [f.applications, f.desktop]) } catch { rejected = true }
            try expect(rejected)
            try expect(try String(contentsOf: f.applications) == "one")
            try expect(try String(contentsOf: f.desktop) == "two")
        }
        test("Uninstall removes only aliases targeting this installed app") { f, manager in
            try manager.create(app: f.app, locations: [f.applications])
            let other = f.root.appendingPathComponent("Other/EvenBetterTouchTool.app"); try Fixture.makeApp(other)
            try manager.create(app: other, locations: [f.desktop])
            let removed = try manager.remove(app: f.app, locations: [f.applications, f.desktop])
            try expect(removed == [f.applications] && FileManager.default.fileExists(atPath: f.desktop.path))
            try expect(FileManager.default.fileExists(atPath: f.app.path))
        }
        test("System Applications installation does not create a self alias") { f, manager in
            try expect(try manager.create(app: f.app, locations: [f.app, f.desktop]) == f.app)
            try expect(!FileManager.default.fileExists(atPath: f.desktop.path))
        }
        test("Shortcut cleanup never deletes a directly installed application") { f, manager in
            try expect(try manager.remove(app: f.app, locations: [f.app]).isEmpty)
            try expect(FileManager.default.fileExists(atPath: f.app.appendingPathComponent("Contents/Info.plist").path))
        }
        test("Cleanup preserves settings and the application") { f, manager in
            let settings = f.root.appendingPathComponent("config.json"); try Data("settings".utf8).write(to: settings)
            try manager.create(app: f.app, locations: [f.applications]); try manager.remove(app: f.app, locations: [f.applications])
            try expect(try String(contentsOf: settings) == "settings")
            try expect(FileManager.default.fileExists(atPath: f.app.path))
        }
        test("Invalid application targets fail before creating a shortcut") { f, manager in
            let invalid = f.root.appendingPathComponent("Invalid.app"); try Fixture.makeApp(invalid, id: "org.example.invalid")
            var rejected = false
            do { try manager.create(app: invalid, locations: [f.applications]) } catch { rejected = true }
            try expect(rejected && !FileManager.default.fileExists(atPath: f.applications.path))
        }
        test("Managed symbolic links can be cleaned without deleting their target") { f, manager in
            try FileManager.default.createSymbolicLink(at: f.applications, withDestinationURL: f.app)
            try expect(manager.state(app: f.app, shortcut: f.applications) == .managed)
            try manager.remove(app: f.app, locations: [f.applications])
            try expect(!FileManager.default.fileExists(atPath: f.applications.path) && FileManager.default.fileExists(atPath: f.app.path))
        }
        test("Full shortcut lifecycle creates, survives update, and cleans up") { f, manager in
            try manager.create(app: f.app, locations: [f.applications, f.desktop])
            try FileManager.default.removeItem(at: f.app); try Fixture.makeApp(f.app)
            try manager.create(app: f.app, locations: [f.applications, f.desktop])
            try manager.remove(app: f.app, locations: [f.applications, f.desktop])
            try expect(!FileManager.default.fileExists(atPath: f.applications.path) && !FileManager.default.fileExists(atPath: f.desktop.path))
            try expect(FileManager.default.fileExists(atPath: f.app.path))
        }
        print("\n\(passed) installer tests passed; \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
