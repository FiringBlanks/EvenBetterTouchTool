import SwiftUI
import AppKit

private let trackpadPane = "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"
private let accessibilityPane = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
private let inputPane = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
private let pointerPane = "x-apple.systempreferences:com.apple.Accessibility-Settings.extension"
private let keyboardPane = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

struct SettingsRoot: View {
    @ObservedObject var model: AppModel
    private let sections: [(String,String)] = [("Dashboard","square.grid.2x2"),("Gestures","hand.draw"),("Applications","app.badge"),("Sensitivity","slider.horizontal.3"),("Trackpad Calibration","ruler"),("Setup Assistant","checklist"),("General","gearshape"),("Diagnostics","waveform.path.ecg")]
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Label("EvenBetterTouchTool", systemImage: "hand.draw.fill").font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.65).padding([.top,.horizontal],16)
                Text("Make every movement count.").font(.caption).foregroundStyle(.secondary).padding(.horizontal,16)
                List(selection: $model.section) {
                    ForEach(sections, id: \.0) { item in Label(item.0, systemImage: item.1).tag(item.0).padding(.vertical,5) }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 5) {
                    Label(model.config.enabled ? "Gestures enabled" : "Gestures paused", systemImage: model.config.enabled ? "circle.fill" : "pause.circle.fill").foregroundStyle(model.config.enabled ? .green : .orange)
                    Text("⌃⌥⌘ Esc • Emergency disable").font(.caption2).foregroundStyle(.secondary)
                }.font(.caption).padding(16)
            }.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.section).font(.largeTitle.bold())
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Enable", isOn: $model.config.enabled).toggleStyle(.switch).accessibilityLabel("Enable gesture engine")
                }.padding(24)
                Divider()
                if !model.message.isEmpty {
                    HStack { Image(systemName:"exclamationmark.triangle"); Text(model.message).font(.caption); Spacer(); Button("Dismiss") { model.message = "" } }.padding(12).background(.orange.opacity(0.12))
                }
                detail
            }.background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 940, minHeight: 660)
    }
    private var subtitle: String {
        switch model.section {
        case "Gestures": return "Three or four fingers. Your choice of action."
        case "Trackpad Calibration": return "Physical distance, measured for your trackpad."
        case "Setup Assistant": return "Resolve macOS conflicts before enabling custom input."
        case "Diagnostics": return "Live contact data and action feedback."
        default: return "A lightweight trackpad utility for macOS."
        }
    }
    @ViewBuilder private var detail: some View {
        switch model.section {
        case "Gestures": GestureGrid(model: model)
        case "Applications": ApplicationsView(model: model)
        case "Sensitivity": Form { SensitivityControls(value: $model.config.sensitivity) }.formStyle(.grouped)
        case "Trackpad Calibration": CalibrationView(model: model)
        case "Setup Assistant": SetupView(model: model)
        case "General": GeneralView(model: model)
        case "Diagnostics": DiagnosticsView(model: model)
        default: DashboardView(model: model)
        }
    }
}
struct DashboardView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section("Engine") {
                LabeledContent("Status", value: model.engineStatus)
                if !model.configurationIssue.isEmpty { Text("Actions paused: \(model.configurationIssue)").foregroundStyle(.orange) }
                LabeledContent("Selected trackpad", value: model.devices.first { $0.id == model.activeDevice }?.name ?? "Disconnected")
                LabeledContent("Foreground application", value: "\(model.foregroundName) • \(model.foreground)")
                LabeledContent("Configured custom mappings", value: String(Gesture.all.filter { let m = model.config.mapping($0, app: model.foreground); return m.enabled && ![.none,.native].contains(m.action.kind) }.count))
                LabeledContent("Ready custom mappings", value: String(Gesture.all.filter { model.config.blockedReason($0, mapping: model.config.mapping($0, app: model.foreground), device: model.activeDevice) == nil }.count))
            }
            Section("Permissions") {
                permission("Accessibility", granted: model.accessibility, pane: accessibilityPane)
                permission("Input Monitoring", granted: model.inputMonitoring, pane: inputPane)
                LabeledContent("Physical button observation", value: model.buttonObserver ? "Available" : "Unavailable — taps paused")
                Button("Check / Request Permissions") { model.requestPermissions() }
            }
            Section("Get ready") {
                Label(model.config.safety.nativeConflictsResolved ? "Native gesture setup confirmed" : "Native gesture setup required", systemImage: "checklist")
                Label(model.config.calibrations[model.activeDevice]?.valid == true ? "Trackpad distance calibrated" : "Trackpad calibration required", systemImage: "ruler")
                HStack { Button("Open Setup Assistant") { model.section = "Setup Assistant" }; Button("Calibrate Trackpad") { model.section = "Trackpad Calibration" } }
                Text("Custom mappings remain paused until setup and calibration are complete. Native pass-through never sends synthetic desktop commands.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Recovery") {
                Text("Press Control–Option–Command–Escape anywhere to disable custom gestures. The menu bar switch and Quit remain available.")
                Button("Disable All Custom Gestures", role: .destructive) { model.emergencyDisable() }
                if !model.legacyPIDs.isEmpty { Text("Original daemon detected: \(model.legacyPIDs.map(String.init).joined(separator: ", ")). Run the local install.sh, then recheck.").foregroundStyle(.orange); Button("Recheck Original Daemon") { model.scanLegacy() } }
            }
        }.formStyle(.grouped)
    }
    private func permission(_ name: String, granted: Bool, pane: String) -> some View {
        HStack { Label(name, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(granted ? .green : .orange); Spacer(); Button(granted ? "Open Settings" : "Grant Permission") { model.openSettings(pane) } }
    }
}
struct GestureGrid: View {
    @ObservedObject var model: AppModel
    @State private var selected: Gesture?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Configuration", selection: $model.selectedProfile) {
                    Text("Global").tag("")
                    ForEach(model.config.profiles) { p in Text(p.name).tag(p.bundleID) }
                }.pickerStyle(.menu)
                Text(model.selectedProfile.isEmpty ? "Global mappings apply unless an enabled app profile overrides them." : "Unedited cells inherit the global mapping. Edit a cell to create an override; Restore Default removes it.").font(.callout).foregroundStyle(.secondary)
                Grid(horizontalSpacing: 8, verticalSpacing: 12) {
                    GridRow { Text("Fingers").font(.caption); ForEach(Direction.allCases, id: \.self) { Text($0.title).font(.caption.weight(.semibold)).frame(maxWidth: .infinity) } }
                    ForEach([3,4], id: \.self) { fingers in
                        GridRow {
                            VStack { Image(systemName: "hand.draw").font(.title2); Text("\(fingers)").font(.title.bold()) }.frame(width: 46)
                            ForEach(Direction.allCases, id: \.self) { d in
                                cell(Gesture(fingers: fingers, direction: d))
                            }
                        }
                    }
                }
                Label("Physical click mappings are disabled: this build cannot reliably correlate and suppress a trackpad press on Tahoe.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                Text("Continuous actions use physical distance. One-shot actions fire once until all fingers lift. A small settling window allows fingers to land together.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.sheet(item: $selected) { g in MappingEditor(model: model, gesture: g).frame(width: 640, height: 700) }
    }
    private func cell(_ g: Gesture) -> some View {
        let m = model.mapping(g)
        return Button { selected = g } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol(g.direction)).font(.title3)
                Text(m.action.kind.title).font(.caption.weight(.medium)).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 32)
                Text(g.direction == .click ? "Unsupported" : !m.enabled ? "Disabled" : m.continuous && m.action.kind.repeatable ? "Continuous" : "Single").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(10).frame(maxWidth: .infinity, minHeight: 120)
                .background(m.enabled && g.direction != .click ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.15)))
        }.buttonStyle(.plain).accessibilityLabel("\(g.title): \(m.action.kind.title)")
    }
    private func symbol(_ d: Direction) -> String {
        switch d { case .left: return "arrow.left"; case .right: return "arrow.right"; case .up: return "arrow.up"; case .down: return "arrow.down"; case .tap: return "hand.tap"; case .click: return "cursorarrow.click" }
    }
}
struct MappingEditor: View {
    @ObservedObject var model: AppModel
    let gesture: Gesture
    @Environment(\.dismiss) private var dismiss
    private var mapping: Binding<Mapping> { Binding(get: { model.mapping(gesture) }, set: { model.setMapping($0, gesture: gesture) }) }
    var body: some View {
        VStack(spacing: 0) {
            HStack { VStack(alignment:.leading) { Text(gesture.title.capitalized).font(.title2.bold()); Text(model.selectedProfile.isEmpty ? "Global configuration" : model.selectedProfile).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(20)
            Divider()
            Form {
                if gesture.direction == .click {
                    Section { Text("Physical multi-finger click remapping is unavailable. MultitouchSupport provides contacts, but pressure/density fields are not a reliable press signal. Mouse events do not identify their originating device, so intercepting them could swallow another mouse's click. Normal physical clicks remain native; they cancel tap recognition.") }
                }
                Section("Action") {
                    Toggle("Enable this gesture", isOn: mapping.enabled).disabled(gesture.direction == .click)
                    Picker("Assigned action", selection: mapping.action.kind) {
                        ForEach(["Navigation","Media / System","Mouse / Keyboard","Applications","Miscellaneous"], id: \.self) { category in
                            Section(category) { ForEach(ActionKind.allCases.filter { $0.category == category }) { kind in Text(kind.title).tag(kind) } }
                        }
                    }.disabled(gesture.direction == .click)
                    ActionParameters(action: mapping.action, model: model)
                    if mapping.wrappedValue.action.kind == .notificationCenter { Text("No stable public API opens Notification Center. Assign a custom shortcut after configuring one in macOS Keyboard Shortcuts.").foregroundStyle(.orange) }
                }
                if gesture.direction.isSwipe {
                    Section("Movement") {
                        Toggle("Continuous distance-based actions", isOn: mapping.continuous).disabled(!mapping.wrappedValue.action.kind.repeatable)
                        Text(mapping.wrappedValue.action.kind.repeatable ? "No time-based repeat. Movement stops → actions stop." : "This action fires once per contact session to avoid overlapping system animations.").font(.caption).foregroundStyle(.secondary)
                        Toggle("Override distance interval", isOn: Binding(get: { mapping.wrappedValue.distanceMM != nil }, set: { mapping.wrappedValue.distanceMM = $0 ? 1 : nil }))
                        if mapping.wrappedValue.distanceMM != nil { NumericSlider(title: "Distance per action", value: Binding(get: { mapping.wrappedValue.distanceMM ?? 1 }, set: { mapping.wrappedValue.distanceMM = $0 }), range: 0.5...20, unit: "mm") }
                        Toggle("Use opposite direction's mapping", isOn: mapping.reverse)
                        NumericSlider(title: "Cooldown (distance during cooldown is discarded)", value: mapping.cooldown, range: 0...5, unit: "s")
                    }
                }
                Section("Availability") {
                    Text(model.config.blockedReason(gesture, mapping: mapping.wrappedValue, device: model.activeDevice) ?? "Ready when required permissions are granted").font(.callout)
                    if gesture.fingers == 4 && [.left,.right].contains(gesture.direction) { Text("Custom reassignment requires disabling native “Swipe between full-screen applications” in System Settings and confirming it in Setup Assistant. Native pass-through never sends a desktop shortcut.").foregroundStyle(.orange) }
                    Button("Restore Default") { model.restoreMapping(gesture) }
                }
            }.formStyle(.grouped)
        }
    }
}
struct ActionParameters: View {
    @Binding var action: Action
    @ObservedObject var model: AppModel
    var body: some View {
        Group {
            if [.volumeUp,.volumeDown].contains(action.kind) {
                Toggle("Override volume step", isOn: Binding(get: { action.volumePercent != nil }, set: { action.volumePercent = $0 ? 2 : nil }))
                if action.volumePercent != nil { NumericSlider(title: "Volume step", value: Binding(get: { action.volumePercent ?? 2 }, set: { action.volumePercent = $0 }), range: 0.1...20, unit: "%") }
            }
            if [.openApplication,.activateApplication,.applicationShortcut].contains(action.kind) {
                TextField("Application bundle ID", text: $action.bundleID)
                Button("Choose Application…") { model.chooseApplication { id, _ in action.bundleID = id } }
            }
            if [.shortcut,.sequence,.applicationShortcut].contains(action.kind) {
                ForEach(action.kind == .shortcut ? Array(action.shortcuts.indices.prefix(1)) : Array(action.shortcuts.indices), id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Shortcut \(i+1)").font(.headline); Spacer(); if action.shortcuts.count > 1 { Button("Remove") { action.shortcuts.remove(at: i) } } }
                        ShortcutControls(shortcut: $action.shortcuts[i])
                    }.padding(.vertical,6)
                }
                if action.kind != .shortcut { Button("Add Shortcut") { if action.shortcuts.count < 32 { action.shortcuts.append(Shortcut()) } } }
                Text("Sequences run in order, once per gesture, and cancel when focus or settings change. Key codes use the Mac ANSI layout; modifiers apply to every key-down/up pair.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
struct ShortcutControls: View {
    @Binding var shortcut: Shortcut
    var body: some View {
        Picker("Key", selection: $shortcut.keyCode) {
            ForEach(KeyCodes.values.keys.sorted(), id: \.self) { key in Text(key.replacingOccurrences(of:"_", with:" ")).tag(KeyCodes.values[key]!) }
        }
        HStack {
            ForEach(["control","option","shift","command","fn"], id: \.self) { name in
                Toggle(name == "control" ? "⌃" : name == "option" ? "⌥" : name == "shift" ? "⇧" : name == "command" ? "⌘" : "fn", isOn: Binding(get: { shortcut.modifiers.contains(name) }, set: { enabled in shortcut.modifiers.removeAll { $0 == name }; if enabled { shortcut.modifiers.append(name) } })).accessibilityLabel(name)
            }
        }
        NumericSlider(title: "Delay after key in sequence", value: $shortcut.delay, range: 0...2, unit: "s")
    }
}
struct NumericSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.callout)
            HStack {
                Slider(value: $value, in: range).accessibilityLabel(title)
                TextField(title, value: Binding(get: { value }, set: { if $0.isFinite { value = min(range.upperBound,max(range.lowerBound,$0)) } }), format: .number.precision(.fractionLength(2))).frame(width: 65).textFieldStyle(.roundedBorder).accessibilityLabel(title)
                Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 24, alignment: .leading)
            }
        }
    }
}
struct SensitivityControls: View {
    @Binding var value: Sensitivity
    var body: some View {
        Section("Continuous movement") {
            NumericSlider(title:"Horizontal distance per action",value:$value.horizontalMM,range:0.5...20,unit:"mm")
            NumericSlider(title:"Vertical distance per action",value:$value.verticalMM,range:0.5...20,unit:"mm")
            NumericSlider(title:"Volume per movement interval",value:$value.volumePercent,range:0.1...20,unit:"%")
        }
        Section("Recognition") {
            NumericSlider(title:"Tap maximum duration",value:$value.tapDuration,range:0.05...1,unit:"s")
            NumericSlider(title:"Tap movement tolerance",value:$value.tapToleranceMM,range:0.1...5,unit:"mm")
            NumericSlider(title:"Swipe activation distance",value:$value.activationMM,range:0.1...10,unit:"mm")
            NumericSlider(title:"Axis dominance (higher rejects more diagonals)",value:$value.diagonalRatio,range:1.05...4,unit:"×")
            NumericSlider(title:"Jitter deadband",value:$value.jitterMM,range:0...0.5,unit:"mm")
        }
        Text("Changes take effect immediately. Lift fingers after editing. Continuous gestures retain fractional distance within a direction; reversing starts from the turning point.").font(.caption).foregroundStyle(.secondary)
    }
}
struct ApplicationsView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var showInstalled = false
    var body: some View {
        Form {
            Section("Application profiles") {
                Text("Enabled app override → global mapping → no action / native pass-through. Disable a cell to stop inheritance for that gesture.").font(.caption).foregroundStyle(.secondary)
                ForEach(model.config.profiles.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        appIcon(model.config.profiles[i].bundleID)
                        VStack(alignment: .leading) { Text(model.config.profiles[i].name).font(.headline); Text(model.config.profiles[i].bundleID).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Toggle("Enabled", isOn: $model.config.profiles[i].enabled).labelsHidden().accessibilityLabel("Enable \(model.config.profiles[i].name) profile")
                        Button("Edit") { model.selectedProfile = model.config.profiles[i].bundleID }
                        Button(role: .destructive) { model.config.profiles.remove(at: i); model.selectedProfile = "" } label: { Image(systemName: "trash") }.accessibilityLabel("Remove application profile")
                    }
                }
                HStack { Button("Add Application…") { model.chooseApplication { id, name in model.addProfile(id:id,name:name) } }; Button(showInstalled ? "Hide Installed Apps" : "Browse Installed Apps") { showInstalled.toggle() } }
            }
            if showInstalled {
                Section("Installed apps") {
                    TextField("Filter applications", text: $query)
                    ForEach(model.installed.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { app in
                        HStack { Image(nsImage:NSWorkspace.shared.icon(forFile:app.url.path)).resizable().frame(width:24,height:24); Text(app.name); Spacer(); Button("Add Profile") { model.addProfile(id:app.id,name:app.name) } }
                    }
                }
            }
            if let index = model.config.profiles.firstIndex(where: { $0.bundleID == model.selectedProfile }) {
                Section("Selected: \(model.config.profiles[index].name)") {
                    Button("Edit Gesture Grid") { model.section = "Gestures" }
                    Toggle("Override global sensitivity", isOn: Binding(get: { model.config.profiles[index].sensitivity != nil }, set: { model.config.profiles[index].sensitivity = $0 ? model.config.sensitivity : nil }))
                    Button("Restore App Defaults") { let p = model.config.profiles[index]; model.config.profiles[index] = Configuration.defaultProfile(p.bundleID,name:p.name) }
                }
                if model.config.profiles[index].sensitivity != nil {
                    SensitivityControls(value: Binding(get: { model.config.profiles[index].sensitivity ?? model.config.sensitivity }, set: { model.config.profiles[index].sensitivity = $0 }))
                }
            }
        }.formStyle(.grouped)
    }
    private func appIcon(_ id: String) -> some View {
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier:id).map { NSWorkspace.shared.icon(forFile:$0.path) } ?? NSImage(systemSymbolName:"app",accessibilityDescription:nil)!
        return Image(nsImage:image).resizable().frame(width:32,height:32)
    }
}
struct CalibrationView: View {
    @ObservedObject var model: AppModel
    @State private var distance = 30.0
    private var calibration: Binding<Calibration> { Binding(get: { model.config.calibrations[model.activeDevice] ?? Calibration() }, set: { model.config.calibrations[model.activeDevice] = $0 }) }
    var body: some View {
        Form {
            Section("Selected device") {
                Picker("Trackpad", selection: $model.config.selectedDevice) { Text("Select trackpad").tag(""); ForEach(model.devices) { Text($0.name).tag($0.id) } }
                if let device = model.devices.first(where: { $0.id == model.activeDevice }) {
                    LabeledContent("Sensor surface (raw units)",value:"\(device.rawWidth) × \(device.rawHeight)")
                }
                Text("Raw sensor dimensions and absolute coordinates have no documented millimeter unit. This app never treats them as physical dimensions. Calibrate X and Y separately, or enter measured active-surface dimensions. Calibration is stored per device ID.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Live test area") {
                TrackpadCanvas(contacts:model.snapshot.contacts).frame(height:160)
                LabeledContent("Touching fingers",value:String(model.snapshot.fingers))
                Text("Finger positions are normalized from 0 to 1. Lift all fingers between trials.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Calibration wizard") {
                Text("Use a ruler to mark a known travel distance on the trackpad. Begin a trial, place ONE finger, move straight along the chosen axis by that distance, then lift. Custom actions pause during measurement.")
                HStack {
                    TextField("Measured travel (mm)",value:$distance,format:.number).frame(width:180)
                    Button("Measure X") { model.startCalibration("X") }.disabled(model.activeDevice.isEmpty)
                    Button("Measure Y") { model.startCalibration("Y") }.disabled(model.activeDevice.isEmpty)
                }
                if let axis = model.calibrationAxis {
                    LabeledContent("Measuring \(axis)",value:"\(model.calibrationTravel.formatted(.number.precision(.fractionLength(4)))) normalized")
                    HStack { Button("Apply Measurement") { model.finishCalibration(distance:distance) }; Button("Cancel") { model.cancelCalibration() } }
                }
            }
            Section("Physical coordinate scale") {
                HStack { Text("Active width (mm)"); Spacer(); TextField("Width",value:calibration.widthMM,format:.number).frame(width:90) }
                HStack { Text("Active height (mm)"); Spacer(); TextField("Height",value:calibration.heightMM,format:.number).frame(width:90) }
                Toggle("I measured and verified both axes",isOn:calibration.confirmed).disabled(!((20...300).contains(calibration.wrappedValue.widthMM) && (20...300).contains(calibration.wrappedValue.heightMM)))
                Label(calibration.wrappedValue.valid ? "Calibrated — distance gestures available" : "Not calibrated — custom mappings paused",systemImage:calibration.wrappedValue.valid ? "checkmark.circle" : "ruler").foregroundStyle(calibration.wrappedValue.valid ? .green : .orange)
            }.disabled(model.activeDevice.isEmpty)
        }.formStyle(.grouped)
    }
}
struct TrackpadCanvas: View {
    var contacts: [Contact]
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius:18).fill(Color.secondary.opacity(0.08))
                RoundedRectangle(cornerRadius:18).strokeBorder(Color.secondary.opacity(0.3))
                if contacts.isEmpty { Label("Touch the selected trackpad",systemImage:"hand.draw").foregroundStyle(.secondary) }
                ForEach(contacts, id: \.id) { c in
                    Circle().fill(Color.accentColor.opacity(0.8)).frame(width:22,height:22).overlay(Text(String(c.id)).font(.system(size:9)).foregroundStyle(.white)).position(x:c.x*geo.size.width,y:(1-c.y)*geo.size.height)
                }
            }
        }.accessibilityLabel("Live trackpad: \(contacts.count) fingers")
    }
}
struct SetupView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section("1 · Grant permissions") {
                Text("Grant EvenBetterTouchTool.app Accessibility and Input Monitoring. These grants belong to the built app, independently of the old command-line daemon. Quit and reopen after changing Input Monitoring.")
                HStack { Button("Request Permissions") { model.requestPermissions() }; Button("Accessibility") { model.openSettings(accessibilityPane) }; Button("Input Monitoring") { model.openSettings(inputPane) } }
            }
            Section("2 · Resolve native swipe conflicts") {
                Text("In Trackpad → More Gestures:")
                Text("• Mission Control: Off\n• App Exposé: Off\n• Swipe between full-screen applications: Swipe with FOUR fingers\n• Swipe between pages: Two fingers only, or Off\n• Notification Center: keep its native two-finger edge gesture")
                Text("In Accessibility → Pointer Control → Trackpad Options: turn OFF three-finger dragging (choose another dragging mode if needed). These settings free three-finger horizontal/vertical swipes and four-finger vertical swipes. The app supplies Mission Control/App Exposé through verified keyboard shortcuts.")
                HStack { Button("Open Trackpad Settings") { model.openSettings(trackpadPane) }; Button("Open Pointer Control") { model.openSettings(pointerPane) } }
                Toggle("I resolved the swipe and dragging conflicts above",isOn:$model.config.safety.nativeConflictsResolved)
                Text("The app observes contacts; it cannot selectively suppress macOS gestures. This confirmation records your manual setup. Revisit it if you change native gestures later.").font(.caption).foregroundStyle(.secondary)
            }
            Section("3 · Resolve tap conflicts") {
                Text("In Trackpad → Point & Click: turn OFF “Look up & data detectors” and “Tap to click”. Keep three-finger dragging OFF. This conservative setup prevents ordinary tap clicks and native Look Up during custom multi-finger taps. Physical clicks still work normally and cancel custom tap recognition.")
                Toggle("I disabled Look Up, Tap to click, and three-finger dragging",isOn:$model.config.safety.tapConflictsResolved)
                Text("Taps also require a working mouse-button observer. Physical click remapping is disabled. No mouse events are swallowed.").font(.caption).foregroundStyle(.secondary)
            }
            Section("4 · Verify system shortcuts and calibrate") {
                Text("In Keyboard → Keyboard Shortcuts → Mission Control, enable and verify Mission Control and Application windows. The app reads explicit configured shortcuts when available. If none can be read, use General → System Shortcuts to confirm a fallback. Then calibrate the trackpad.")
                HStack { Button("Keyboard Settings") { model.openSettings(keyboardPane) }; Button("System Shortcuts") { model.section = "General" }; Button("Calibrate") { model.section = "Trackpad Calibration" } }
            }
            Section("Optional · Reassign four-finger horizontal swipes") {
                Text("Leave this OFF for native desktop switching. To customize these swipes, first turn OFF “Swipe between full-screen applications” in Trackpad settings. Native pass-through mappings always send no synthetic command.")
                Toggle("I disabled native horizontal four-finger desktop swipes",isOn:$model.config.safety.nativeHorizontalDisabled)
            }
            Section("Recovery") {
                Text("Control–Option–Command–Escape disables custom actions globally. You can also use the menu bar switch or Quit. Setup never changes macOS preferences automatically.")
            }
        }.formStyle(.grouped)
    }
}
struct GeneralView: View {
    @ObservedObject var model: AppModel
    @State private var resetAlert = false
    private let systemActions: [ActionKind] = [.missionControl,.appExpose,.showDesktop,.previousDesktop,.nextDesktop]
    var body: some View {
        Form {
            Section("Startup and appearance") {
                Toggle("Start at Login",isOn:Binding(get:{model.loginEnabled},set:{model.setLogin($0)}))
                Button("Open macOS Login Items") { model.openLoginItems() }
                Toggle("Enable Gesture Engine",isOn:$model.config.enabled)
                Toggle("Run in Menu Bar Only",isOn:$model.config.menuBarOnly)
                Text("When menu bar only is enabled, the app has no permanent Dock icon. Login startup uses macOS Login Items and requires an installed .app.").font(.caption).foregroundStyle(.secondary)
                Button("Check Permissions") { model.requestPermissions() }
            }
            Section("Configuration") {
                Text(model.store.url.path).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                HStack { Button("Export Settings…") { model.exportSettings() }; Button("Import Settings…") { model.importSettings() } }
                HStack { Button("Open Configuration File") { model.save(); NSWorkspace.shared.open(model.store.url) }; Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.url]) } }
                Button("Restore Defaults…",role:.destructive) { resetAlert = true }
                Text("Settings save automatically and external JSON edits reload within two seconds. Imports back up the current file and reset local setup confirmations/calibration.").font(.caption).foregroundStyle(.secondary)
            }
            Section("System Shortcuts") {
                Text("Explicit macOS keyboard settings take precedence. If a setting is absent, enter the shortcut you verified in System Settings and enable its fallback. The app never assumes Control–Left/Right is configured.").font(.caption).foregroundStyle(.secondary)
                ForEach(systemActions) { kind in
                    DisclosureGroup(kind.title) {
                        Text(SystemShortcuts.resolve(kind).map { "Read from macOS: key \($0.keyCode), \($0.modifiers.joined(separator:" + "))" } ?? "No enabled shortcut could be read from macOS")
                        Toggle("Use my verified fallback if macOS setting is unavailable",isOn:Binding(get:{model.config.systemShortcuts[kind.rawValue] != nil},set:{ enabled in
                            if enabled { model.config.systemShortcuts[kind.rawValue] = fallback(kind) } else { model.config.systemShortcuts.removeValue(forKey:kind.rawValue) }
                        }))
                        if model.config.systemShortcuts[kind.rawValue] != nil {
                            ShortcutControls(shortcut:Binding(get:{model.config.systemShortcuts[kind.rawValue] ?? fallback(kind)},set:{model.config.systemShortcuts[kind.rawValue] = $0}))
                        }
                    }
                }
                Button("Open Keyboard Shortcuts") { model.openSettings(keyboardPane) }
            }
            Section("About") {
                LabeledContent("Application version",value:AppModel.version)
                Text("Free and open source • MIT license • Native Apple Silicon • No analytics or network updater")
                Button("Check Application Version") { model.message = "Installed version: \(AppModel.version). This local build has no automatic updater; build updates from your reviewed source." }
            }
        }.formStyle(.grouped).alert("Restore all default settings?",isPresented:$resetAlert) {
            Button("Cancel",role:.cancel) {}; Button("Restore",role:.destructive) { model.restoreDefaults() }
        } message: { Text("Your current configuration will be backed up. Calibration and setup confirmations will need to be completed again.") }
    }
    private func fallback(_ kind: ActionKind) -> Shortcut {
        switch kind {
        case .missionControl: return Shortcut(keyCode:126,modifiers:["control"])
        case .appExpose: return Shortcut(keyCode:125,modifiers:["control"])
        case .previousDesktop: return Shortcut(keyCode:123,modifiers:["control"])
        case .nextDesktop: return Shortcut(keyCode:124,modifiers:["control"])
        default: return Shortcut(keyCode:103,modifiers:[])
        }
    }
}
struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section("Live contacts") {
                TrackpadCanvas(contacts:model.snapshot.contacts).frame(height:140)
                LabeledContent("Fingers",value:String(model.snapshot.fingers))
                LabeledContent("Movement (calibrated)",value:"X \(model.snapshot.dxMM.formatted(.number.precision(.fractionLength(3)))) mm • Y \(model.snapshot.dyMM.formatted(.number.precision(.fractionLength(3)))) mm")
                ForEach(model.snapshot.contacts,id:\.id) { c in Text("#\(c.id): x=\(c.x.formatted(.number.precision(.fractionLength(4))))  y=\(c.y.formatted(.number.precision(.fractionLength(4))))").font(.system(.caption,design:.monospaced)) }
            }
            Section("Recognition and actions") {
                LabeledContent("Detected gesture",value:model.snapshot.gesture)
                LabeledContent("Availability / cancellation",value:model.snapshot.reason.isEmpty ? "Ready" : model.snapshot.reason)
                LabeledContent("Last action / result",value:model.lastAction)
                LabeledContent("Last action timestamp",value:model.lastActionDate?.formatted(date:.omitted,time:.standard) ?? "None")
                LabeledContent("Foreground app",value:model.foreground)
                LabeledContent("Sensitivity",value:"X \(model.config.sensitivity(for:model.foreground).horizontalMM) mm • Y \(model.config.sensitivity(for:model.foreground).verticalMM) mm")
                LabeledContent("Device",value:model.engineStatus)
            }
            Section("Diagnostics log") {
                Toggle("Enable local in-memory action logging",isOn:$model.config.logging)
                HStack { Button("Copy Diagnostic Information") { model.copyDiagnostics() }; Button("Clear Log") { model.log = [] }; Button("Reconnect Trackpad") { model.driver.reconnect() }; Button("Check Legacy Daemon") { model.scanLegacy() } }
                Text(model.log.suffix(50).joined(separator:"\n")).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                Text("At most 250 action records are retained in memory. No typing or trackpad coordinates are written to disk. Hardware tests are described in docs/MANUAL-TESTS.md.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
