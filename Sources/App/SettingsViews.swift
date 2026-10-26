import SwiftUI
import AppKit

private let trackpadPane = "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"
private let accessibilityPane = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
private let inputPane = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
private let pointerPane = "x-apple.systempreferences:com.apple.Accessibility-Settings.extension"
private let keyboardPane = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

/// A fixed blue track conveys the selected value even when macOS deactivates the window.
struct PersistentBlueSwitchStyle: ToggleStyle {
    func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Button { configuration.isOn.toggle() } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Color(red: 0, green: 0.48, blue: 1) : Color.secondary.opacity(0.28))
                    Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                }.frame(width: 38, height: 22)
            }.buttonStyle(.plain)
        }.accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}
struct PermissionControls: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ForEach(PrivacyPermission.allCases) { permission in
            let granted = permission == .accessibility ? model.accessibility : model.inputMonitoring
            HStack(spacing: 12) {
                Label(permission.title, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(granted ? .green : .orange)
                Spacer()
                Text(granted ? "Verified" : "Not verified").font(.caption).foregroundStyle(.secondary)
                Button(granted ? "Open Settings" : "Set Up…") {
                    if granted { model.openSettings(permission.settingsURL) } else { model.requestPermission(permission) }
                }
            }
        }
        if !model.accessibility || !model.inputMonitoring {
            VStack(alignment: .leading, spacing: 8) {
                Text("In the permission list, click +. In the file picker press ⌘⇧G, paste this app path, press Return, then click Open and enable its switch.").font(.callout)
                Text(model.applicationURL.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack { Button("Copy App Path") { model.copyApplicationPath() }; Button("Show App in Finder") { model.revealApplication() } }
                Text("If Accessibility already looks enabled, relaunch the app. If it still says Not verified, remove that entry with − and add this installed copy again. Local app updates can invalidate an older grant.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: 560, alignment: .leading).padding(.vertical, 4)
        }
        HStack {
            Button("Recheck Permissions") { model.checkPermissions() }
            Button("Relaunch App") { model.relaunch() }.disabled(model.hasPendingChanges)
                .help("Save or Reset pending edits first. Relaunch never autosaves settings.")
        }
    }
}
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
                    Label(model.readyMappingCount > 0 ? "Custom gestures ready" : "Custom gestures paused", systemImage: model.readyMappingCount > 0 ? "circle.fill" : "pause.circle.fill").foregroundStyle(model.readyMappingCount > 0 ? .green : .orange)
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
                    Toggle(model.config.enabled ? "Enabled" : "Disabled", isOn: $model.config.enabled).toggleStyle(PersistentBlueSwitchStyle()).accessibilityLabel("Enable gesture engine")
                }.padding(24)
                Divider()
                if !model.message.isEmpty {
                    HStack { Image(systemName:"exclamationmark.triangle"); Text(model.message).font(.caption); Spacer(); Button("Dismiss") { model.message = "" } }.padding(12).background(.orange.opacity(0.12))
                }
                detail
                Divider()
                HStack(spacing: 12) {
                    Text(model.editing.externalConflict ? "External changes — Reset to review" : model.hasPendingChanges ? "Unsaved changes" : model.runtimePaused ? "Emergency pause active" : "All changes saved")
                        .font(.caption).foregroundStyle(model.hasPendingChanges || model.editing.externalConflict ? .orange : .secondary)
                    Spacer()
                    Button("Reset") { model.resetEdits() }.disabled(!model.hasPendingChanges && !model.editing.externalConflict)
                    Button("Save") { NSApp.keyWindow?.makeFirstResponder(nil); DispatchQueue.main.async { model.save() } }
                        .buttonStyle(.borderedProminent).disabled(!model.canSave || model.calibrationAxis != nil)
                        .keyboardShortcut("s", modifiers: .command)
                }.padding(.horizontal, 24).padding(.vertical, 14)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 940, minHeight: 660)
    }
    private var subtitle: String {
        switch model.section {
        case "Gestures": return "Three or four fingers. Your choice of action."
        case "Trackpad Calibration": return "Live tracking and optional precision measurements."
        case "Setup Assistant": return "Resolve macOS conflicts before enabling custom input."
        case "Diagnostics": return "Live contact data and action feedback."
        default: return "A lightweight trackpad utility for macOS."
        }
    }
    @ViewBuilder private var detail: some View {
        switch model.section {
        case "Gestures": GestureGrid(model: model)
        case "Applications": ApplicationsView(model: model)
        case "Sensitivity": Form { SensitivityControls(value: $model.config.sensitivity, unit: model.distanceUnit) }.formStyle(.grouped)
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
            Section("Gesture readiness") {
                Label(model.readyMappingCount > 0 ? "Custom gestures are ready" : "Custom gestures are paused", systemImage: model.readyMappingCount > 0 ? "checkmark.circle.fill" : "pause.circle.fill")
                    .font(.headline).foregroundStyle(model.readyMappingCount > 0 ? .green : .orange)
                ForEach(model.gestureBlockers) { blocker in Label(blocker.title, systemImage: "circle").font(.callout) }
                HStack { Button("Open Setup Assistant") { model.section = "Setup Assistant" }; Button("Trackpad & Optional Calibration") { model.section = "Trackpad Calibration" } }
                if model.hasPendingChanges { Text("Pending setup or calibration changes also need Save.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Permissions") { PermissionControls(model: model) }
            Section("Engine") {
                LabeledContent("Contact stream", value: model.engineStatus)
                if !model.configurationIssue.isEmpty { Text("Actions paused: \(model.configurationIssue)").foregroundStyle(.orange) }
                LabeledContent("Selected trackpad", value: model.devices.first { $0.id == model.activeDevice }?.name ?? "Disconnected")
                LabeledContent("Foreground application", value: "\(model.foregroundName) • \(model.foreground)")
                LabeledContent("Configured custom mappings", value: String(Gesture.all.filter { let m = model.savedConfig.mapping($0, app: model.foreground); return m.enabled && ![.none,.native].contains(m.action.kind) }.count))
                LabeledContent("Ready custom mappings", value: String(model.readyMappingCount))
                LabeledContent("Physical button observation", value: model.buttonObserver ? "Available" : "Unavailable — taps paused")
                LabeledContent("Custom gesture scroll filter", value: model.scrollFiltering ? "Active" : "Unavailable — custom swipes paused")
                if !model.savedConfig.safety.tapConflictsResolved { Text("Custom taps also need the tap-conflict confirmation in Setup Assistant and Save.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Recovery") {
                Text("Press Control–Option–Command–Escape anywhere to disable custom gestures. The menu bar switch and Quit remain available.")
                Button("Disable All Custom Gestures", role: .destructive) { model.emergencyDisable() }
                if !model.legacyPIDs.isEmpty { Text("Original daemon detected: \(model.legacyPIDs.map(String.init).joined(separator: ", ")). Run the local install.sh, then recheck.").foregroundStyle(.orange); Button("Recheck Original Daemon") { model.scanLegacy() } }
            }
        }.formStyle(.grouped)
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
                Text("Click a cell to edit, a hand to toggle a row, or ↕ to swap a column.").font(.callout).foregroundStyle(.secondary)
                Grid(horizontalSpacing: 8, verticalSpacing: 12) {
                    GridRow { Text("Fingers").font(.caption); ForEach(Direction.allCases, id: \.self) { Text($0.title).font(.caption.weight(.semibold)).frame(maxWidth: .infinity) } }
                    ForEach([3,4], id: \.self) { fingers in
                        GridRow {
                            rowToggle(fingers)
                            ForEach(Direction.allCases, id: \.self) { d in cell(Gesture(fingers: fingers, direction: d)) }
                        }
                        if fingers == 3 {
                            GridRow {
                                Text("Swap").font(.caption2).foregroundStyle(.secondary)
                                ForEach(Direction.allCases,id:\.self) { direction in
                                    Button { model.swapRows(direction) } label: {
                                        Image(systemName:"arrow.up.arrow.down").font(.system(size:12,weight:.medium)).frame(width:24,height:22)
                                    }.buttonStyle(.borderless).controlSize(.small).frame(maxWidth:.infinity)
                                        .accessibilityLabel("Swap three- and four-finger \(direction.title) mappings")
                                        .help("Swap \(direction.title) settings between three and four fingers. Click Save to apply.")
                                }
                            }
                        }
                    }
                }
                Label("Physical press actions also perform the normal mouse click. Native pass-through is unaffected by row switches.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.popover(item: $selected, arrowEdge: .bottom) { g in
            MappingEditor(model: model, gesture: g, profileID: model.selectedProfile).frame(width: 600, height: 620)
        }
    }
    private func rowToggle(_ fingers: Int) -> some View {
        let enabled = model.rowEnabled(fingers)
        return Button { model.toggleRow(fingers) } label: {
            VStack(spacing: 6) {
                Image(systemName: enabled ? "hand.draw.fill" : "hand.draw").font(.title2)
                Text("\(fingers)").font(.title.bold())
                HStack(spacing: 3) { Circle().frame(width: 5, height: 5); Text(enabled ? "On" : "Off").font(.caption2) }
            }.foregroundStyle(enabled ? Color.accentColor : Color.secondary).frame(width: 52, height: 116)
                .background(enabled ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel("\(fingers)-finger row: \(enabled ? "Enabled" : "Disabled")")
            .help("\(enabled ? "Disable" : "Enable") all \(fingers)-finger custom gestures. Click Save to apply.")
    }
    private func cell(_ g: Gesture) -> some View {
        let m = model.mapping(g), rowEnabled = model.rowEnabled(g.fingers)
        return Button { selected = g } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol(g.direction)).font(.title3)
                Text(m.action.kind.title).font(.caption.weight(.medium)).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 32)
                Text(!rowEnabled ? "Row disabled" : !m.enabled ? "Disabled" : m.continuous && m.action.supportsContinuous ? "Continuous" : "Single").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(10).frame(maxWidth: .infinity, minHeight: 120)
                .background(rowEnabled && m.enabled ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.15)))
                .opacity(rowEnabled ? 1 : 0.5)
        }.buttonStyle(.plain).accessibilityLabel("\(g.title): \(m.action.kind.title)\(rowEnabled ? "" : ", row disabled")")
    }
    private func symbol(_ d: Direction) -> String {
        switch d { case .left: return "arrow.left"; case .right: return "arrow.right"; case .up: return "arrow.up"; case .down: return "arrow.down"; case .tap: return "hand.tap"; case .click: return "cursorarrow.click" }
    }
}
struct MappingEditor: View {
    @ObservedObject var model: AppModel
    let gesture: Gesture
    let profileID: String
    private let initial: Mapping
    private let initiallyInherited: Bool
    @State private var draft: Mapping
    @State private var inherited: Bool
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss
    init(model: AppModel, gesture: Gesture, profileID: String) {
        self.model = model; self.gesture = gesture; self.profileID = profileID
        let mapping = model.editing.mapping(gesture, profileID: profileID)
        let inherit = !profileID.isEmpty && model.editing.override(gesture, profileID: profileID) == nil
        initial = mapping; initiallyInherited = inherit
        _draft = State(initialValue: mapping); _inherited = State(initialValue: inherit)
    }
    private var changed: Bool { draft != initial || inherited != initiallyInherited }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(gesture.title.capitalized).font(.title2.bold())
                    Text(profileID.isEmpty ? "Global configuration" : model.config.profiles.first { $0.bundleID == profileID }?.name ?? profileID).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Close without saving").help("Close without saving").keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            Form {
                if gesture.direction == .click { Section { Text("Runs on release of a physical mouse press while the required fingers rest on the selected trackpad. The normal mouse click still happens. Another mouse can also trigger it while those fingers are resting.").font(.callout) } }
                if !profileID.isEmpty {
                    Section {
                        Toggle("Use global mapping", isOn: $inherited)
                        if inherited { Button("Customize for This App") { inherited = false } }
                    }
                }
                Section("Action") {
                    Toggle("Enable this gesture", isOn: $draft.enabled)
                    LabeledContent("Assigned action") {
                        Menu {
                            ForEach(["Navigation","Media / System","Mouse / Keyboard","Applications","Miscellaneous"], id: \.self) { category in
                                Menu(category) {
                                    ForEach(ActionKind.allCases.filter { $0.category == category }) { kind in
                                        Button { draft.action.kind = kind } label: {
                                            if draft.action.kind == kind { Label(kind.title,systemImage:"checkmark") }
                                            else { Text(kind.title) }
                                        }
                                    }
                                }
                            }
                        } label: { Text(draft.action.kind.title) }
                        .accessibilityLabel("Assigned action: \(draft.action.kind.title)")
                        .help("Choose from Navigation, Media / System, Mouse / Keyboard, Applications, or Miscellaneous.")
                    }
                    ActionParameters(action: $draft.action, model: model)
                    if draft.action.kind == .notificationCenter { Text("Assign a custom keyboard shortcut to open Notification Center.").foregroundStyle(.orange) }
                }.disabled(inherited)
                if gesture.direction == .tap {
                    Section("Tap settings") {
                        Toggle("Override tap settings", isOn: Binding(get: { draft.tapOptions != nil }, set: { draft.tapOptions = $0 ? model.config.sensitivity(for:profileID).effectiveTapOptions : nil }))
                        if draft.tapOptions != nil {
                            TapControls(value:Binding(get:{draft.tapOptions ?? TapOptions()},set:{draft.tapOptions=$0}),unit:model.distanceUnit)
                        }
                        NumericSlider(title:"Gesture cooldown",value:$draft.cooldown,range:0...3,unit:"s")
                    }.disabled(inherited)
                }
                if gesture.direction == .click {
                    Section("Physical press settings") {
                        Toggle("Override press settings",isOn:Binding(get:{draft.clickOptions != nil},set:{draft.clickOptions = $0 ? model.config.sensitivity(for:profileID).effectiveClickOptions : nil}))
                        if draft.clickOptions != nil {
                            PressControls(value:Binding(get:{draft.clickOptions ?? ClickOptions()},set:{draft.clickOptions=$0}),unit:model.distanceUnit)
                        }
                        NumericSlider(title:"Gesture cooldown",value:$draft.cooldown,range:0...3,unit:"s")
                    }.disabled(inherited)
                }
                if gesture.direction.isSwipe {
                    Section("Movement") {
                        Toggle("Continuous", isOn: Binding(get: { draft.continuous && draft.action.supportsContinuous }, set: { draft.continuous = $0 }))
                            .disabled(!draft.action.supportsContinuous)
                        if let reason = draft.action.continuousUnavailableReason {
                            Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("Override distance", isOn: Binding(get: { draft.distanceMM != nil }, set: { draft.distanceMM = $0 ? 1 : nil }))
                        if draft.distanceMM != nil { NumericSlider(title: "Distance per action", value: Binding(get: { draft.distanceMM ?? 1 }, set: { draft.distanceMM = $0 }), range: 0.5...20, unit: model.distanceUnit) }
                        Toggle("Reverse direction", isOn: $draft.reverse)
                        NumericSlider(title: "Cooldown", value: $draft.cooldown, range: 0...5, unit: "s").help([ActionKind.volumeUp,.volumeDown].contains(draft.action.kind) ? "Volume steps are retained during cooldown and applied on the next movement after it ends." : "Movement during a cooldown is discarded.")
                    }.disabled(inherited)
                }
                Section {
                    if gesture.fingers == 4 && [.left,.right].contains(gesture.direction) && draft.action.kind != .native {
                        Text("Disable native desktop swipes in Setup Assistant before assigning a custom action.").font(.caption).foregroundStyle(.orange)
                    }
                    Button("Restore Default") { restoreDefault() }
                    if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Button("Reset") { draft = initial; inherited = initiallyInherited; error = "" }.disabled(!changed)
                Spacer()
                Button("Save") {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    DispatchQueue.main.async {
                        if model.saveMapping(inherited ? nil : draft, gesture: gesture, profileID: profileID) { dismiss() }
                        else { error = model.message }
                    }
                }.buttonStyle(.borderedProminent).disabled(!changed)
            }.padding(16)
        }
    }
    private func restoreDefault() {
        let value = profileID.isEmpty ? Configuration.defaults.mappings[gesture.id] : Configuration.defaultProfile(profileID, name: "").mappings[gesture.id]
        inherited = !profileID.isEmpty && value == nil
        draft = value ?? model.config.mappings[gesture.id] ?? Mapping(enabled: false)
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
                Picker("Application", selection: $action.bundleID) {
                    Text("Choose application").tag("")
                    if !action.bundleID.isEmpty && !model.installed.contains(where: { $0.id == action.bundleID }) { Text(action.bundleID).tag(action.bundleID) }
                    ForEach(model.installed) { app in Text(app.name).tag(app.id) }
                }
            }
            if [.shortcut,.sequence,.applicationShortcut].contains(action.kind) {
                ForEach(action.kind == .shortcut ? Array(action.shortcuts.indices.prefix(1)) : Array(action.shortcuts.indices), id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Shortcut \(i+1)").font(.headline); Spacer(); if action.shortcuts.count > 1 { Button("Remove") { action.shortcuts.remove(at: i) } } }
                        ShortcutControls(shortcut: $action.shortcuts[i], showDelay: action.kind != .shortcut && action.shortcuts.count > 1)
                    }.padding(.vertical,6)
                }
                if action.kind != .shortcut { Button("Add Shortcut") { if action.shortcuts.count < 32 { action.shortcuts.append(Shortcut()) } } }
            }
        }
    }
}
struct ShortcutControls: View {
    @Binding var shortcut: Shortcut
    var showDelay = false
    var body: some View {
        Picker("Key", selection: $shortcut.keyCode) {
            ForEach(KeyCodes.values.keys.sorted(), id: \.self) { key in Text(key.replacingOccurrences(of:"_", with:" ")).tag(KeyCodes.values[key]!) }
        }
        HStack {
            ForEach(["control","option","shift","command","fn"], id: \.self) { name in
                Toggle(name == "control" ? "⌃" : name == "option" ? "⌥" : name == "shift" ? "⇧" : name == "command" ? "⌘" : "fn", isOn: Binding(get: { shortcut.modifiers.contains(name) }, set: { enabled in shortcut.modifiers.removeAll { $0 == name }; if enabled { shortcut.modifiers.append(name) } })).accessibilityLabel(name)
            }
        }
        if showDelay { NumericSlider(title: "Step delay", value: $shortcut.delay, range: 0...2, unit: "s") }
    }
}
struct NumericSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var unit: String
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(title).font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                TextField("", value: Binding(get: { value }, set: { if $0.isFinite { value = min(range.upperBound,max(range.lowerBound,$0)) } }), format: .number.precision(.fractionLength(2)))
                    .frame(width: 68).textFieldStyle(.roundedBorder).accessibilityLabel(title)
                Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 24, alignment: .leading)
            }
            Slider(value: $value, in: range).labelsHidden().accessibilityLabel(title)
        }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TapControls: View {
    @Binding var value: TapOptions
    var unit: String
    var body: some View {
        NumericSlider(title:"Maximum tap duration",value:$value.duration,range:0.05...1.5,unit:"s")
        NumericSlider(title:"Finger movement tolerance",value:$value.movement,range:0.1...10,unit:unit)
        NumericSlider(title:"Swipe cancels tap",value:$value.swipeCancellation,range:0.1...10,unit:unit)
        NumericSlider(title:"Finger landing window",value:$value.landingWindow,range:0...0.4,unit:"s")
        NumericSlider(title:"Finger lift window",value:$value.releaseWindow,range:0.02...0.5,unit:"s")
        NumericSlider(title:"Tap cooldown",value:$value.cooldown,range:0...2,unit:"s")
        NumericSlider(title:"Wait for physical click",value:$value.clickDelay,range:0...0.25,unit:"s")
        NumericSlider(title:"Click exclusion window",value:$value.clickExclusion,range:0.02...0.5,unit:"s")
        Text("A triggered swipe or physical press always cancels its tap. Changes require Save.").font(.caption).foregroundStyle(.secondary)
    }
}
struct PressControls: View {
    @Binding var value: ClickOptions
    var unit: String
    var body: some View {
        Picker("Mouse button",selection:$value.button) { Text("Primary").tag(0); Text("Secondary").tag(1); Text("Middle").tag(2) }
        NumericSlider(title:"Contact freshness",value:$value.contactAge,range:0.02...0.5,unit:"s")
        NumericSlider(title:"Fingers resting before press",value:$value.settleTime,range:0...0.3,unit:"s")
        NumericSlider(title:"Finger landing grace after press",value:$value.landingWindow,range:0...0.3,unit:"s")
        NumericSlider(title:"Maximum press duration",value:$value.maxDuration,range:0.1...10,unit:"s")
        NumericSlider(title:"Press movement tolerance",value:$value.movement,range:0.1...20,unit:unit)
        NumericSlider(title:"Press cooldown",value:$value.cooldown,range:0...3,unit:"s")
        Toggle("Ignore synthesized mouse presses",isOn:$value.ignoreSynthetic)
    }
}
struct SensitivityControls: View {
    @Binding var value: Sensitivity
    var unit: String
    var body: some View {
        Section("Continuous movement") {
            Text(unit == "mm" ? "Measured distance on the selected trackpad." : "No calibration needed. Distances are percentages of the trackpad’s width or height.").font(.caption).foregroundStyle(.secondary)
            NumericSlider(title:"Horizontal interval",value:$value.horizontalMM,range:0.5...20,unit:unit)
            NumericSlider(title:"Vertical interval",value:$value.verticalMM,range:0.5...20,unit:unit)
            NumericSlider(title:"Volume step",value:$value.volumePercent,range:0.1...20,unit:"%")
        }
        Section("Taps") {
            TapControls(value:$value.effectiveTapOptions,unit:unit)
        }
        Section("Physical presses") {
            PressControls(value:$value.effectiveClickOptions,unit:unit)
        }
        Section("Recognition") {
            NumericSlider(title:"Swipe activation",value:$value.activationMM,range:0.1...10,unit:unit)
            NumericSlider(title:"Diagonal rejection",value:$value.diagonalRatio,range:1.05...4,unit:"×")
            NumericSlider(title:"Jitter tolerance",value:$value.jitterMM,range:0...0.5,unit:unit)
        }
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
                    SensitivityControls(value: Binding(get: { model.config.profiles[index].sensitivity ?? model.config.sensitivity }, set: { model.config.profiles[index].sensitivity = $0 }), unit: model.distanceUnit)
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
    @State private var showPrecision = false
    private var calibration: Binding<Calibration> {
        Binding(get: { model.config.calibrations[model.activeDevice] ?? Calibration() }, set: { value in
            var updated = value
            let previous = model.config.calibrations[model.activeDevice] ?? Calibration()
            if previous.widthMM != value.widthMM || previous.heightMM != value.heightMM { updated.confirmed = false }
            model.config.calibrations[model.activeDevice] = updated
        })
    }
    private var deviceUnavailable: Bool { model.activeDevice.isEmpty || (!model.config.selectedDevice.isEmpty && model.config.selectedDevice != model.activeDevice) }
    var body: some View {
        Form {
            Section("Trackpad sensitivity") {
                Label(calibration.wrappedValue.valid ? "Using measured millimeters" : "Ready to use without calibration", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Calibration is optional. By default, one tab switch uses 1% of the trackpad’s width; one volume step uses 4% of its height. Adjust these intervals in Sensitivity. Measure only if you want exact millimeters.")
                Button("Adjust Sensitivity") { model.section = "Sensitivity" }
                if calibration.wrappedValue.valid {
                    Button("Use Relative Sensitivity") { model.useRelativeSensitivity() }.disabled(deviceUnavailable)
                    Text("Click Save to apply the change. The interval numbers stay the same; their unit changes from mm to %.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Selected device") {
                Picker("Trackpad", selection: Binding(get: { model.config.selectedDevice.isEmpty ? model.activeDevice : model.config.selectedDevice }, set: { model.config.selectedDevice = $0 })) { Text("Select trackpad").tag(""); ForEach(model.devices) { Text($0.name).tag($0.id) } }
                if deviceUnavailable { Text("Connect a trackpad, or Save your device selection first.").foregroundStyle(.secondary) }
            }
            Section("Live test area") {
                TrackpadCanvas(contacts:model.snapshot.contacts).frame(height:160)
                LabeledContent("Touching fingers",value:String(model.snapshot.fingers))
                Text("Move one or more fingers to check tracking. This test needs no confirmation or calibration.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("Precision calibration (optional)", isExpanded: Binding(get: { showPrecision || model.calibrationAxis != nil }, set: { showPrecision = $0 || model.calibrationAxis != nil })) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Enter the measured active-surface dimensions, then click Use Measurements and Save. Both dimensions must be between 20 and 300 mm.").font(.callout)
                        HStack { Text("Active width (mm)"); Spacer(); TextField("Width",value:calibration.widthMM,format:.number).frame(width:90).accessibilityLabel("Measured active width in millimeters") }
                        HStack { Text("Active height (mm)"); Spacer(); TextField("Height",value:calibration.heightMM,format:.number).frame(width:90).accessibilityLabel("Measured active height in millimeters") }
                        Button("Use Measurements") { model.confirmCalibrationDimensions() }.disabled(!calibration.wrappedValue.dimensionsValid || model.calibrationAxis != nil)
                        if calibration.wrappedValue.valid { Text("Measurements staged. Click Save to apply; Reset discards edits.").font(.caption).foregroundStyle(.secondary) }
                        Divider()
                        Text("Alternatively, measure each axis with one finger: start a trial, move a ruler-measured distance in a straight line, then lift.").font(.callout)
                        HStack {
                            TextField("Travel (mm)",value:$distance,format:.number).frame(width:150).accessibilityLabel("Measured finger travel in millimeters")
                            Button("Measure X") { model.startCalibration("X") }.disabled(model.calibrationAxis != nil)
                            Button("Measure Y") { model.startCalibration("Y") }.disabled(model.calibrationAxis != nil)
                        }
                        if let axis = model.calibrationAxis {
                            Text(model.calibrationInstruction).font(.callout)
                            LabeledContent("Measuring \(axis)",value:"\((model.calibrationTravel*100).formatted(.number.precision(.fractionLength(1))))% of axis")
                            HStack { Button("Use Trial") { model.finishCalibration(distance:distance) }; Button("Cancel Trial") { model.cancelCalibration() } }
                        }
                    }.padding(.top, 8).disabled(deviceUnavailable)
                }
            }
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
                PermissionControls(model: model)
            }
            Section("2 · Resolve native swipe conflicts") {
                Text("In Trackpad → More Gestures:")
                Text("• Mission Control / App Exposé: disable the native feature when assigning a custom action; keep it enabled for Native Pass Through\n• Swipe between full-screen applications: Swipe with FOUR fingers\n• Swipe between pages: Two fingers only, or Off\n• Notification Center: keep its native two-finger edge gesture")
                Text("In Accessibility → Pointer Control → Trackpad Options: turn OFF three-finger dragging (choose another dragging mode if needed). For example, keep native four-finger Mission Control enabled if swipe up is Pass Through; turn native App Exposé off if swipe down is a custom Show Desktop action. Custom system actions use verified keyboard shortcuts.")
                HStack { Button("Open Trackpad Settings") { model.openSettings(trackpadPane) }; Button("Open Pointer Control") { model.openSettings(pointerPane) } }
                Toggle("I resolved the swipe and dragging conflicts above",isOn:$model.config.safety.nativeConflictsResolved)
                Text("The scroll filter prevents ordinary page scrolling during custom swipes. It cannot suppress native Mission Control, App Exposé, dragging, or other WindowServer gestures. Revisit this setup if you change mappings.").font(.caption).foregroundStyle(.secondary)
            }
            Section("3 · Resolve tap conflicts") {
                Text("In Trackpad → Point & Click: turn OFF “Look up & data detectors” and “Tap to click”. Keep three-finger dragging OFF. This conservative setup prevents ordinary tap clicks and native Look Up during custom multi-finger taps. Physical clicks still work normally and cancel custom tap recognition.")
                Toggle("I disabled Look Up, Tap to click, and three-finger dragging",isOn:$model.config.safety.tapConflictsResolved)
                Text("Taps also require a working mouse-button observer. Physical press actions retain the normal mouse click. No mouse-button events are swallowed.").font(.caption).foregroundStyle(.secondary)
            }
            Section("4 · Verify system shortcuts") {
                Text("In Keyboard → Keyboard Shortcuts → Mission Control, enable and verify Mission Control and Application windows. The app reads explicit configured shortcuts when available. If none can be read, use General → System Shortcuts to confirm a fallback. Calibration is optional; relative sensitivity works without measurements.")
                HStack { Button("Keyboard Settings") { model.openSettings(keyboardPane) }; Button("System Shortcuts") { model.section = "General" }; Button("Optional Calibration") { model.section = "Trackpad Calibration" } }
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
                HStack { Button("Open Configuration File") { if FileManager.default.fileExists(atPath: model.store.url.path) { NSWorkspace.shared.open(model.store.url) } else { model.message = "Click Save to create the configuration file first." } }; Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.url]) } }
                Button("Restore Defaults…",role:.destructive) { resetAlert = true }
                Text("Changes, imports, and restored defaults remain pending until Save. Reset discards pending edits.").font(.caption).foregroundStyle(.secondary)
            }
            Section("System Shortcuts") {
                Text("Explicit macOS keyboard settings take precedence. If a setting is absent, enter the shortcut you verified in System Settings and enable its fallback. The app never assumes Control–Left/Right is configured.").font(.caption).foregroundStyle(.secondary)
                ForEach(systemActions) { kind in
                    DisclosureGroup(kind.title) {
                        Text(SystemShortcuts.choice(kind) == .disabled ? "Disabled in macOS Keyboard Shortcuts. Enable it there before using this action." : SystemShortcuts.resolve(kind).map { "Read from macOS: key \($0.keyCode), \($0.modifiers.joined(separator:" + "))" } ?? "No explicit shortcut is stored by macOS. Verify its setting below and Save a fallback.")
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
        } message: { Text("Defaults will be staged for review. Click Save to apply them, or Reset to keep your saved settings.") }
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
                LabeledContent("Movement (\(model.savedConfig.movementScale(for: model.activeDevice).title))",value:"X \(model.snapshot.dxMM.formatted(.number.precision(.fractionLength(3)))) \(model.savedDistanceUnit) • Y \(model.snapshot.dyMM.formatted(.number.precision(.fractionLength(3)))) \(model.savedDistanceUnit)")
                ForEach(model.snapshot.contacts,id:\.id) { c in Text("#\(c.id): x=\(c.x.formatted(.number.precision(.fractionLength(4))))  y=\(c.y.formatted(.number.precision(.fractionLength(4))))").font(.system(.caption,design:.monospaced)) }
            }
            Section("Recognition and actions") {
                LabeledContent("Scroll interception",value:model.scrollFiltering ? "Active for custom swipes" : "Unavailable")
                LabeledContent("Detected gesture",value:model.snapshot.gesture)
                LabeledContent("Availability / cancellation",value:model.snapshot.reason.isEmpty ? "Ready" : model.snapshot.reason)
                LabeledContent("Last action / result",value:model.lastAction)
                LabeledContent("Last action timestamp",value:model.lastActionDate?.formatted(date:.omitted,time:.standard) ?? "None")
                LabeledContent("Foreground app",value:model.foreground)
                LabeledContent("Sensitivity",value:"X \(model.savedConfig.sensitivity(for:model.foreground).horizontalMM) \(model.savedDistanceUnit) • Y \(model.savedConfig.sensitivity(for:model.foreground).verticalMM) \(model.savedDistanceUnit)")
                LabeledContent("Device",value:model.engineStatus)
            }
            Section("Test system actions") {
                Text("Send one action now to check keyboard delivery independently of gesture detection. App Exposé applies to the foreground app.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Test Mission Control") { model.testSystemAction(.missionControl) }
                    Button("Test App Exposé") { model.testSystemAction(.appExpose) }
                    Button("Test Show Desktop") { model.testSystemAction(.showDesktop) }
                }.disabled(!model.accessibility)
                Button("Preview Volume Indicator") { model.previewVolumeIndicator() }
                LabeledContent("Volume indicator",value:model.volumeIndicatorVisible ? "Visible" : "Hidden")
                Text("The preview shows 42% without changing system volume. During volume gestures it shows the actual output level and closes after two seconds.").font(.caption).foregroundStyle(.secondary)
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
