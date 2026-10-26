import SwiftUI
import AppKit

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
    @State private var showHelp = false
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
                DisclosureGroup("Permission troubleshooting",isExpanded:$showHelp) {
                    Text("If an enabled permission stays unverified after relaunching, remove the old entry with −, add this installed copy again, and enable it. Local builds may need a fresh approval after updates.").font(.caption).foregroundStyle(.secondary).padding(.top,6)
                }
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
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Label("EvenBetterTouchTool", systemImage: "hand.draw.fill").font(.headline).lineLimit(1).minimumScaleFactor(0.8).padding([.top,.horizontal],16)
                List(selection: $model.section) {
                    ForEach(SettingsSection.allCases) { section in Label(section.rawValue, systemImage: section.symbol).tag(section.rawValue).padding(.vertical,5) }
                }.listStyle(.sidebar)
                Text("⌃⌥⌘ Esc · Emergency disable").font(.caption2).foregroundStyle(.secondary).padding(16)
            }.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.section).font(.largeTitle.bold())
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
    @ViewBuilder private var detail: some View {
        switch model.section {
        case SettingsSection.gestures.rawValue: GestureGrid(model: model)
        case SettingsSection.sensitivity.rawValue: SensitivitySettingsView(model: model)
        default: SetupSettingsView(model: model)
        }
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
                        Text("Disable the conflicting desktop swipes in Setup → macOS gestures before assigning a custom action.").font(.caption).foregroundStyle(.orange)
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
