import Foundation

@main struct AppModelTests {
    static var passed = 0, failed = 0
    static func expect(_ condition: @autoclosure () throws -> Bool) throws { if try !condition() { throw ConfigError.invalid("Expectation failed") } }
    static func test(_ name: String, _ body: (AppModel, URL) throws -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("EvenBetterTouchTool-tests-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            let url = dir.appendingPathComponent("config.json")
            try ConfigurationStore(url: url).save(.defaults)
            let model = AppModel(configurationURL: url)
            try body(model, url); model.stop()
            passed += 1; print("PASS \(name)")
        } catch { failed += 1; print("FAIL \(name): \(error)") }
    }
    static func main() throws {
        test("Editing and waiting do not autosave") { model, url in
            let before = try Data(contentsOf: url)
            model.config.sensitivity.horizontalMM = 8
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            try expect(try Data(contentsOf: url) == before)
            try expect(model.savedConfig.sensitivity.horizontalMM == 1 && model.hasPendingChanges)
        }
        test("Explicit Save persists and applies pending changes") { model, url in
            model.config.sensitivity.horizontalMM = 8
            try expect(model.save())
            try expect(try ConfigurationStore(url: url).load().sensitivity.horizontalMM == 8)
            try expect(model.savedConfig.sensitivity.horizontalMM == 8 && !model.hasPendingChanges)
        }
        test("Quit does not save pending edits") { model, url in
            let before = try Data(contentsOf: url)
            model.config.enabled = false; model.stop()
            try expect(try Data(contentsOf: url) == before)
        }
        test("Reset changes neither the saved file nor running settings") { model, url in
            let before = try Data(contentsOf: url)
            model.config.sensitivity.horizontalMM = 8; model.resetEdits()
            try expect(!model.hasPendingChanges && model.config == model.savedConfig)
            try expect(try Data(contentsOf: url) == before)
        }
        test("Gesture Save does not save other sections") { model, url in
            model.config.sensitivity.horizontalMM = 8
            let g = Gesture(fingers: 3, direction: .tap), m = Mapping(action: Action(kind: .nextTrack))
            try expect(model.saveMapping(m, gesture: g, profileID: ""))
            let saved = try ConfigurationStore(url: url).load()
            try expect(saved.mappings[g.id] == m && saved.sensitivity.horizontalMM == 1)
            try expect(model.config.sensitivity.horizontalMM == 8 && model.hasPendingChanges)
        }
        test("Import is pending until Save") { model, url in
            let before = try Data(contentsOf: url), source = url.deletingLastPathComponent().appendingPathComponent("import.json")
            var imported = Configuration.defaults; imported.sensitivity.horizontalMM = 7
            try JSONEncoder().encode(imported).write(to: source)
            try model.stageImport(from: source)
            try expect(try Data(contentsOf: url) == before)
            try expect(model.hasPendingChanges && model.config.sensitivity.horizontalMM == 7 && model.savedConfig.sensitivity.horizontalMM == 1)
        }
        test("Restore Defaults is pending until Save") { model, url in
            model.config.sensitivity.horizontalMM = 8; try expect(model.save())
            let before = try Data(contentsOf: url)
            model.restoreDefaults()
            try expect(model.config.sensitivity.horizontalMM == 1 && model.savedConfig.sensitivity.horizontalMM == 8)
            try expect(try Data(contentsOf: url) == before)
        }
        test("Emergency disable is immediate but never persists implicitly") { model, url in
            let before = try Data(contentsOf: url)
            model.emergencyDisable()
            try expect(model.runtimePaused && !model.config.enabled && model.savedConfig.enabled)
            try expect(try Data(contentsOf: url) == before)
            model.resetEdits(); try expect(model.runtimePaused)
        }
        test("Login toggle is staged without changing macOS registration") { model, _ in
            let saved = model.editing.savedLoginEnabled
            model.setLogin(!saved); model.checkPermissions()
            try expect(model.loginEnabled != saved && model.editing.savedLoginEnabled == saved)
        }
        test("Invalid Save does not replace or apply saved settings") { model, url in
            let before = try Data(contentsOf: url)
            model.config.sensitivity.horizontalMM = 0
            try expect(!model.save() && model.savedConfig.sensitivity.horizontalMM == 1)
            try expect(try Data(contentsOf: url) == before)
        }
        test("Row switches are pending until Save") { model, url in
            let before = try Data(contentsOf: url)
            model.toggleRow(3)
            try expect(!model.rowEnabled(3) && model.savedConfig.isRowEnabled(3, app: "com.google.Chrome"))
            try expect(try Data(contentsOf: url) == before)
            try expect(model.save())
            try expect(try !ConfigurationStore(url: url).load().isRowEnabled(3, app: "com.google.Chrome"))
        }
        test("Trackpad discovery does not silently persist device selection") { model, url in
            let before = try Data(contentsOf: url)
            model.driver.onDevices?([TrackpadInfo(id: "discovered", name: "Test trackpad")], "discovered")
            try expect(model.activeDevice == "discovered" && model.config.selectedDevice.isEmpty)
            try expect(try Data(contentsOf: url) == before)
        }
        test("Relaunch refuses unsaved edits without implicitly saving") { model, url in
            let before=try Data(contentsOf:url)
            model.config.sensitivity.horizontalMM=9; model.relaunch()
            try expect(model.hasPendingChanges && model.message.contains("Save or Reset"))
            try expect(try Data(contentsOf:url)==before)
        }
        test("Ready mapping count is zero while either permission is unverified") { model, _ in
            model.config.safety.nativeConflictsResolved=true; model.config.safety.tapConflictsResolved=true
            model.config.calibrations["test"]=Calibration(widthMM:100,heightMM:100,confirmed:true)
            try expect(model.save()); model.activeDevice="test"
            model.accessibility=false; model.inputMonitoring=true
            try expect(model.readyMappingCount==0 && model.gestureBlockers.contains(.accessibility))
            model.accessibility=true; model.inputMonitoring=false
            try expect(model.readyMappingCount==0 && model.gestureBlockers.contains(.inputMonitoring))
            model.inputMonitoring=true
            try expect(model.readyMappingCount>0)
        }
        test("Pending setup confirmations do not falsely mark gestures ready") { model, _ in
            model.activeDevice="test"; model.accessibility=true; model.inputMonitoring=true
            model.config.safety.nativeConflictsResolved=true
            model.config.calibrations["test"]=Calibration(widthMM:100,heightMM:100,confirmed:true)
            try expect(model.readyMappingCount==0 && model.gestureBlockers.contains(.nativeSetup) && model.gestureBlockers.contains(.calibration))
        }
        print("\n\(passed) model tests passed; \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
