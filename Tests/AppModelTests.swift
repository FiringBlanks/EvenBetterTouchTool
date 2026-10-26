import Foundation
import CoreGraphics

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
            model.inputMonitoring=true; model.scrollFiltering=true
            try expect(model.readyMappingCount>0)
        }
        test("Pending setup confirmations do not falsely mark gestures ready") { model, _ in
            model.activeDevice="test"; model.accessibility=true; model.inputMonitoring=true
            model.config.safety.nativeConflictsResolved=true
            model.config.calibrations["test"]=Calibration(widthMM:100,heightMM:100,confirmed:true)
            try expect(model.readyMappingCount==0 && model.gestureBlockers.contains(.nativeSetup) && !model.gestureBlockers.contains(.calibration))
        }
        test("Optional measurements are pending until Save and Reset restores relative units") { model, url in
            model.activeDevice="test"; let before=try Data(contentsOf:url)
            try expect(model.distanceUnit=="%")
            model.config.calibrations["test"]=Calibration(widthMM:150,heightMM:80)
            model.confirmCalibrationDimensions()
            try expect(model.distanceUnit=="mm" && model.savedDistanceUnit=="%" && model.hasPendingChanges)
            try expect(try Data(contentsOf:url)==before)
            model.resetEdits(); try expect(model.distanceUnit=="%" && !model.hasPendingChanges)
        }
        test("Measurements and return to relative sensitivity require explicit Save") { model, url in
            model.activeDevice="test"
            model.config.calibrations["test"]=Calibration(widthMM:150,heightMM:80)
            model.confirmCalibrationDimensions(); try expect(model.save())
            model.activeDevice="test"; try expect(model.savedDistanceUnit=="mm")
            let before=try Data(contentsOf:url); model.useRelativeSensitivity()
            try expect(model.distanceUnit=="%" && model.savedDistanceUnit=="mm")
            try expect(try Data(contentsOf:url)==before)
            try expect(model.save() && model.savedDistanceUnit=="%")
        }
        test("Invalid measured dimensions remain unconfirmed") { model, _ in
            model.activeDevice="test"; model.config.calibrations["test"]=Calibration(widthMM:150,heightMM:0)
            model.confirmCalibrationDimensions()
            try expect(model.distanceUnit=="%" && !model.config.calibrations["test"]!.confirmed && !model.message.isEmpty)
        }
        test("Settings window keeps normal app mode through foreground changes") { model, url in
            let before=try Data(contentsOf:url)
            try expect(!model.wantsDockAndMenu)
            model.setSettingsVisible(true); model.foregroundChanged(); model.apply()
            try expect(model.wantsDockAndMenu)
            model.setSettingsVisible(false); try expect(!model.wantsDockAndMenu)
            model.config.menuBarOnly=false; try expect(model.save() && model.wantsDockAndMenu)
            try expect(before != Data(contentsOf:url))
        }
        test("Continuous sequence edits require explicit gesture Save") { model, url in
            let g=Gesture(fingers:3,direction:.right)
            var mapping=Mapping(action:Action(kind:.sequence,shortcuts:[Shortcut(keyCode:48)]))
            model.config.mappings[g.id]=mapping; try expect(model.save())
            let before=try Data(contentsOf:url)
            mapping.continuous=true
            try expect(mapping.action.supportsContinuous && !model.savedConfig.mappings[g.id]!.continuous)
            try expect(try Data(contentsOf:url)==before)
            try expect(model.saveMapping(mapping,gesture:g,profileID:""))
            try expect(try ConfigurationStore(url:url).load().mappings[g.id]!.continuous)
        }
        test("Indicator preview changes no audio or saved settings") { model, url in
            let before=try Data(contentsOf:url); var levels=[VolumeLevel]()
            model.onVolumeFeedback={ levels.append($0) }; model.previewVolumeIndicator()
            try expect(levels==[VolumeLevel(value:0.42,muted:false)] && !model.hasPendingChanges)
            try expect(try Data(contentsOf:url)==before)
        }
        test("System test rejects missing Accessibility without saving") { model, url in
            let before=try Data(contentsOf:url); model.accessibility=false
            model.testSystemAction(.showDesktop)
            try expect(model.message.contains("Accessibility") && !model.hasPendingChanges)
            try expect(try Data(contentsOf:url)==before)
        }
        test("Quartz system arrow events include real modifier edges and navigation flags") { _, _ in
            let events=KeyboardEvents.make(Shortcut(keyCode:126,modifiers:["control"]))
            try expect(events.count==4 && events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [59,126,126,59])
            try expect(events[1].flags.contains([.maskControl,.maskSecondaryFn,.maskNumericPad]))
            try expect(events[0].type == .flagsChanged && events.last!.type == .flagsChanged && !events.last!.flags.contains(.maskControl))
            try expect(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData)==ActionExecutor.eventTag })
        }
        test("Quartz F11 events preserve function flag without numeric-pad flags") { _, _ in
            let events=KeyboardEvents.make(Shortcut(keyCode:103,modifiers:[]))
            try expect(events.count==2 && events[0].flags.contains(.maskSecondaryFn) && !events[0].flags.contains(.maskNumericPad))
        }
        test("Quartz shortcut does not release a user's held Control key") { _, _ in
            let events=KeyboardEvents.make(Shortcut(keyCode:126,modifiers:["control"]),physical:.maskControl)
            try expect(events.count==2 && events.allSatisfy { $0.flags.contains(.maskControl) && $0.getIntegerValueField(.keyboardEventKeycode)==126 })
        }
        test("Tap and press overrides remain pending until explicit Save") { model, url in
            let before=try Data(contentsOf:url); let g=Gesture(fingers:3,direction:.click)
            model.config.sensitivity.effectiveTapOptions=TapOptions(duration:0.7)
            try expect(try Data(contentsOf:url)==before && model.savedConfig.sensitivity.effectiveTapOptions.duration==0.5)
            let mapping=Mapping(action:Action(kind:.playPause),clickOptions:ClickOptions(contactAge:0.2))
            try expect(model.saveMapping(mapping,gesture:g,profileID:""))
            try expect(model.savedConfig.mappings[g.id]?.enabled==true && model.savedConfig.sensitivity.effectiveTapOptions.duration==0.5 && model.hasPendingChanges)
            model.resetEdits(); try expect(!model.hasPendingChanges && model.config.sensitivity.effectiveTapOptions.duration==0.5)
        }
        test("Restore Defaults stages enabled press playback without saving it") { model, url in
            model.config.mappings["3_click"]?.enabled=false; try expect(model.save())
            let before=try Data(contentsOf:url); model.restoreDefaults()
            try expect(model.config.mappings["3_click"]?.enabled==true && model.config.mappings["3_tap"]?.enabled==false && model.savedConfig.mappings["3_click"]?.enabled==false)
            try expect(try Data(contentsOf:url)==before)
            model.resetEdits(); try expect(model.config.mappings["3_click"]?.enabled==false)
        }
        print("\n\(passed) model tests passed; \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
