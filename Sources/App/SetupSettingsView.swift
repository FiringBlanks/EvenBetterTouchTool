import SwiftUI
import AppKit

private let trackpadPane = "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"
private let pointerPane = "x-apple.systempreferences:com.apple.Accessibility-Settings.extension"
private let keyboardPane = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

/// The full label row is a target, rather than only the small native chevron.
private struct SetupDisclosureStyle:DisclosureGroupStyle {
    func makeBody(configuration:DisclosureGroupStyleConfiguration)->some View {
        VStack(alignment:.leading,spacing:0) {
            Button {
                withAnimation(.easeInOut(duration:0.15)) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing:8) {
                    Image(systemName:"chevron.right").font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary).rotationEffect(.degrees(configuration.isExpanded ? 90:0))
                    configuration.label
                    Spacer(minLength:0)
                }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(configuration.isExpanded ? "Expanded":"Collapsed")
            if configuration.isExpanded { configuration.content.disclosureGroupStyle(SetupDisclosureStyle()).padding(.leading,18).padding(.top,10) }
        }
    }
}

struct SetupSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var showSwipeInstructions = false
    @State private var showTapInstructions = false
    @State private var showInstalled = false
    @State private var query = ""
    @State private var resetAlert = false

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section("Permissions") { PermissionControls(model:model) }.id(SetupTarget.permissions)
                Section("Trackpad") {
                    Picker("Selected trackpad",selection:Binding(get:{model.config.selectedDevice.isEmpty ? model.activeDevice : model.config.selectedDevice},set:{model.config.selectedDevice=$0})) {
                        Text("Select trackpad").tag("")
                        ForEach(model.devices) { Text($0.name.components(separatedBy:" • ").first ?? $0.name).tag($0.id) }
                        if !model.config.selectedDevice.isEmpty && !model.devices.contains(where:{$0.id==model.config.selectedDevice}) { Text("Disconnected trackpad").tag(model.config.selectedDevice) }
                    }.disabled(model.devices.isEmpty)
                    if model.devices.isEmpty { Label("No trackpad connected",systemImage:"exclamationmark.circle").foregroundStyle(.orange) }
                    if !model.configurationIssue.isEmpty { Text(model.configurationIssue).foregroundStyle(.orange) }
                    ForEach(model.gestureBlockers.filter { ![.accessibility,.inputMonitoring,.trackpad,.nativeSetup,.scrollFiltering,.configuration].contains($0) }) { blocker in
                        Label(blocker.title,systemImage:"exclamationmark.circle").font(.callout).foregroundStyle(.orange)
                    }
                    Button("Test Tracking or Calibrate…") { model.showSetup(.calibration) }
                }
                Section("Startup") {
                    Toggle("Start at Login",isOn:Binding(get:{model.loginEnabled},set:{model.setLogin($0)}))
                    Toggle("Run in Menu Bar Only",isOn:$model.config.menuBarOnly)
                    Button("Open macOS Login Items") { model.openLoginItems() }
                }
                Section("macOS gestures") {
                    DisclosureGroup(model.config.safety.nativeConflictsResolved ? "Swipe setup · Confirmed" : "Configure native swipes",isExpanded:$showSwipeInstructions) {
                        VStack(alignment:.leading,spacing:12) {
                            Text("In Trackpad → More Gestures, keep native gestures enabled for Pass Through mappings and disable them for gestures you customize here.")
                            Text("• Swipe between full-screen applications: four fingers\n• Swipe between pages: two fingers or Off\n• Mission Control / App Exposé: disable only the directions assigned custom actions\n• Notification Center: keep its native two-finger edge gesture")
                            Text("Turn off three-finger dragging in Accessibility → Pointer Control → Trackpad Options. The app can block page scrolling during custom swipes, but cannot suppress native macOS gestures.").font(.callout)
                            HStack { Button("Trackpad Settings") { model.openSettings(trackpadPane) }; Button("Pointer Control") { model.openSettings(pointerPane) } }
                            Toggle("I resolved the native swipe and dragging conflicts",isOn:$model.config.safety.nativeConflictsResolved)
                            Toggle("I disabled native four-finger horizontal swipes",isOn:$model.config.safety.nativeHorizontalDisabled)
                            Text("Leave the second confirmation off when desktop swipes use Native Pass Through.").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical,8)
                    }
                    DisclosureGroup(model.config.safety.tapConflictsResolved ? "Tap setup · Confirmed" : "Configure native taps (if used)",isExpanded:$showTapInstructions) {
                        VStack(alignment:.leading,spacing:12) {
                            Text("For custom multi-finger taps, turn off Look up & data detectors and Tap to click in Trackpad → Point & Click, and keep three-finger dragging off. Physical clicks still work normally.")
                            Button("Trackpad Settings") { model.openSettings(trackpadPane) }
                            Toggle("I disabled Look Up, Tap to click, and three-finger dragging",isOn:$model.config.safety.tapConflictsResolved)
                        }.padding(.vertical,8)
                    }
                }
                profiles.id(SetupTarget.applications)
                Section("Settings") {
                    HStack { Button("Import Settings…") { model.importSettings() }; Button("Export Settings…") { model.exportSettings() } }
                    Button("Restore Defaults…",role:.destructive) { resetAlert=true }
                }
                Section {
                    DisclosureGroup("Advanced",isExpanded:Binding(get:{model.showAdvancedSetup},set:{model.showAdvancedSetup=$0 || model.calibrationAxis != nil})) {
                        VStack(alignment:.leading,spacing:16) {
                            DisclosureGroup("Trackpad test & calibration",isExpanded:Binding(get:{model.showCalibrationSetup || model.calibrationAxis != nil},set:{model.showCalibrationSetup=$0 || model.calibrationAxis != nil})) {
                                TrackpadSetupFields(model:model).padding(.top,12)
                            }.id(SetupTarget.calibration)
                            Divider()
                            DisclosureGroup("System shortcuts",isExpanded:$model.showShortcutSetup) { SystemShortcutFields(model:model).padding(.top,12) }.id(SetupTarget.shortcuts)
                            Divider()
                            DisclosureGroup("Diagnostics",isExpanded:$model.showDiagnosticsSetup) { SetupDiagnosticFields(model:model).padding(.top,12) }.id(SetupTarget.diagnostics)
                            Divider()
                            DisclosureGroup("Configuration files") {
                                VStack(alignment:.leading,spacing:12) {
                                    Text(model.store.url.path).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                                    HStack {
                                        Button("Open Configuration File") {
                                            if FileManager.default.fileExists(atPath:model.store.url.path) { NSWorkspace.shared.open(model.store.url) }
                                            else { model.message="Click Save to create the configuration file first." }
                                        }
                                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.url]) }
                                    }
                                }.padding(.top,12)
                            }
                            Divider()
                            DisclosureGroup("Recovery") {
                                VStack(alignment:.leading,spacing:12) {
                                    Text("Control–Option–Command–Escape pauses custom gestures immediately. The menu bar switch and Quit are also available.")
                                    Button("Disable All Custom Gestures",role:.destructive) { model.emergencyDisable() }
                                    Button("Check Original Daemon") { model.scanLegacy() }
                                    if !model.legacyPIDs.isEmpty { Text("Original threefinger is running: \(model.legacyPIDs.map(String.init).joined(separator:", ")). Run the included installer to migrate it safely.").foregroundStyle(.orange) }
                                }.padding(.top,12)
                            }
                        }.padding(.vertical,12)
                    }
                }.id(SetupTarget.advanced)
                Section { LabeledContent("Version",value:AppModel.version) }
            }.formStyle(.grouped).disclosureGroupStyle(SetupDisclosureStyle())
                .onAppear {
                    showSwipeInstructions = !model.savedConfig.safety.nativeConflictsResolved
                    scroll(to:model.setupTarget,using:proxy)
                }
                .onChange(of:model.setupNavigationRevision) { _,_ in scroll(to:model.setupTarget,using:proxy) }
        }.alert("Restore all default settings?",isPresented:$resetAlert) {
            Button("Cancel",role:.cancel) {}
            Button("Restore",role:.destructive) { model.restoreDefaults() }
        } message: { Text("Review the defaults, then click Save to apply them. Reset keeps your saved settings.") }
    }
    private func scroll(to target:SetupTarget,using proxy:ScrollViewProxy) {
        // Expand the destination before scrolling so optional content has a layout.
        DispatchQueue.main.async { withAnimation(.easeInOut(duration:0.2)) { proxy.scrollTo(target,anchor:.top) } }
    }
    private var profiles: some View {
        Section("Application profiles") {
            ForEach(model.config.profiles.indices,id:\.self) { i in
                let profile=model.config.profiles[i]
                HStack(spacing:12) {
                    Image(nsImage:appIcon(profile.bundleID)).resizable().frame(width:28,height:28)
                    Text(profile.name).fontWeight(.medium)
                    Spacer()
                    Toggle("Enabled",isOn:$model.config.profiles[i].enabled).labelsHidden().accessibilityLabel("Enable \(profile.name) profile")
                    Button("Gestures") { model.selectedProfile=profile.bundleID; model.section="Gestures" }.accessibilityLabel("Edit \(profile.name) gestures")
                    Menu {
                        Button("Edit Sensitivity…") { model.selectedProfile=profile.bundleID; model.section="Sensitivity" }
                        Button("Restore App Defaults") { model.config.profiles[i]=Configuration.defaultProfile(profile.bundleID,name:profile.name) }
                        Divider()
                        Button("Remove Profile",role:.destructive) { model.config.profiles.remove(at:i); if model.selectedProfile==profile.bundleID { model.selectedProfile="" } }
                    } label: { Image(systemName:"ellipsis.circle") }.menuIndicator(.hidden).fixedSize().accessibilityLabel("Options for \(profile.name)")
                }
            }
            Button("Add Application…") { model.chooseApplication { id,name in model.addProfile(id:id,name:name) } }
            DisclosureGroup("Browse installed applications",isExpanded:$showInstalled) {
                VStack(spacing:12) {
                    TextField("Search applications",text:$query)
                    ScrollView {
                        LazyVStack(spacing:12) {
                            ForEach(model.installed.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { app in
                                HStack {
                                    Image(nsImage:NSWorkspace.shared.icon(forFile:app.url.path)).resizable().frame(width:24,height:24)
                                    Text(app.name); Spacer()
                                    Button(model.config.profiles.contains { $0.bundleID==app.id } ? "Added" : "Add Profile") { model.addProfile(id:app.id,name:app.name) }.disabled(model.config.profiles.contains { $0.bundleID==app.id })
                                }
                            }
                        }.padding(4)
                    }.frame(height:200)
                }.padding(.top,12)
            }
        }
    }
    private func appIcon(_ id:String) -> NSImage {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier:id).map { NSWorkspace.shared.icon(forFile:$0.path) } ?? NSImage(systemSymbolName:"app",accessibilityDescription:nil)!
    }
}

struct SensitivitySettingsView: View {
    @ObservedObject var model:AppModel
    var body:some View {
        Form {
            Section {
                Picker("Configuration",selection:$model.selectedProfile) { Text("Global").tag(""); ForEach(model.config.profiles) { Text($0.name).tag($0.bundleID) } }
            }
            if let i=model.config.profiles.firstIndex(where:{$0.bundleID==model.selectedProfile}) {
                Section { Toggle("Override global sensitivity",isOn:Binding(get:{model.config.profiles[i].sensitivity != nil},set:{model.config.profiles[i].sensitivity=$0 ? model.config.sensitivity:nil})) }
                SensitivityControls(value:Binding(get:{model.config.profiles[i].sensitivity ?? model.config.sensitivity},set:{model.config.profiles[i].sensitivity=$0}),unit:model.distanceUnit).disabled(model.config.profiles[i].sensitivity == nil)
            } else { SensitivityControls(value:$model.config.sensitivity,unit:model.distanceUnit) }
        }.formStyle(.grouped)
    }
}

struct TrackpadSetupFields:View {
    @ObservedObject var model:AppModel
    @State private var distance=30.0
    @State private var showPrecision=false
    private var calibration:Binding<Calibration> {
        Binding(get:{model.config.calibrations[model.activeDevice] ?? Calibration()},set:{ value in
            var next=value
            let old=model.config.calibrations[model.activeDevice] ?? Calibration()
            if old.widthMM != value.widthMM || old.heightMM != value.heightMM { next.confirmed=false }
            model.config.calibrations[model.activeDevice]=next
        })
    }
    private var unavailable:Bool { model.activeDevice.isEmpty || (!model.config.selectedDevice.isEmpty && model.config.selectedDevice != model.activeDevice) }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            TrackpadCanvas(contacts:model.snapshot.contacts).frame(height:150)
            LabeledContent("Touching fingers",value:String(model.snapshot.fingers))
            LabeledContent("Movement",value:"X \(model.snapshot.dxMM.formatted(.number.precision(.fractionLength(3)))) \(model.savedDistanceUnit) · Y \(model.snapshot.dyMM.formatted(.number.precision(.fractionLength(3)))) \(model.savedDistanceUnit)")
            Text(calibration.wrappedValue.valid ? "Using measured millimeters." : "Calibration is optional. Sensitivity uses percentages of each trackpad axis until measured.").font(.callout).foregroundStyle(.secondary)
            Button("Adjust Sensitivity") { model.section="Sensitivity" }
            DisclosureGroup("Contact coordinates") {
                ForEach(model.snapshot.contacts,id:\.id) { c in Text("#\(c.id): x=\(c.x.formatted(.number.precision(.fractionLength(4))))  y=\(c.y.formatted(.number.precision(.fractionLength(4))))").font(.system(.caption,design:.monospaced)) }
            }
            DisclosureGroup("Precision calibration (optional)",isExpanded:Binding(get:{showPrecision || model.calibrationAxis != nil},set:{showPrecision=$0 || model.calibrationAxis != nil})) {
                VStack(alignment:.leading,spacing:12) {
                    Text("Measure the active surface, enter both dimensions (20–300 mm), then choose Use Measurements and Save.")
                    HStack { Text("Active width"); Spacer(); TextField("Width",value:calibration.widthMM,format:.number).frame(width:90).accessibilityLabel("Measured active width in millimeters"); Text("mm") }
                    HStack { Text("Active height"); Spacer(); TextField("Height",value:calibration.heightMM,format:.number).frame(width:90).accessibilityLabel("Measured active height in millimeters"); Text("mm") }
                    Button("Use Measurements") { model.confirmCalibrationDimensions() }.disabled(!calibration.wrappedValue.dimensionsValid || model.calibrationAxis != nil)
                    if calibration.wrappedValue.valid {
                        Button("Use Relative Sensitivity") { model.useRelativeSensitivity() }
                        Text("The interval numbers stay the same when switching between mm and %.").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("Or measure each axis: start a trial, move one finger a ruler-measured distance, then lift.")
                    HStack {
                        TextField("Travel (mm)",value:$distance,format:.number).frame(width:140).accessibilityLabel("Measured finger travel in millimeters")
                        Button("Measure X") { model.startCalibration("X") }.disabled(model.calibrationAxis != nil)
                        Button("Measure Y") { model.startCalibration("Y") }.disabled(model.calibrationAxis != nil)
                    }
                    if let axis=model.calibrationAxis {
                        Text(model.calibrationInstruction)
                        LabeledContent("Measuring \(axis)",value:"\((model.calibrationTravel*100).formatted(.number.precision(.fractionLength(1))))% of axis")
                        HStack { Button("Use Trial") { model.finishCalibration(distance:distance) }; Button("Cancel Trial") { model.cancelCalibration() } }
                    }
                }.padding(.top,12).disabled(unavailable)
            }
        }
    }
}

struct SystemShortcutFields:View {
    @ObservedObject var model:AppModel
    private let actions:[ActionKind]=[.missionControl,.appExpose,.showDesktop,.previousDesktop,.nextDesktop]
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("macOS shortcuts take precedence. Add a verified fallback only when the system setting cannot be read.").font(.callout).foregroundStyle(.secondary)
            ForEach(actions) { kind in
                DisclosureGroup(kind.title) {
                    VStack(alignment:.leading,spacing:10) {
                        Text(SystemShortcuts.choice(kind) == .disabled ? "Disabled in macOS. Enable it in Keyboard Shortcuts." : SystemShortcuts.resolve(kind).map { "macOS: key \($0.keyCode), \($0.modifiers.joined(separator:" + "))" } ?? "No explicit shortcut found. Verify the fallback in macOS before enabling it.").font(.caption)
                        Toggle("Use my verified fallback",isOn:Binding(get:{model.config.systemShortcuts[kind.rawValue] != nil},set:{model.config.systemShortcuts[kind.rawValue]=$0 ? fallback(kind):nil}))
                        if model.config.systemShortcuts[kind.rawValue] != nil { ShortcutControls(shortcut:Binding(get:{model.config.systemShortcuts[kind.rawValue] ?? fallback(kind)},set:{model.config.systemShortcuts[kind.rawValue]=$0})) }
                    }.padding(.top,10)
                }
            }
            Button("Open Keyboard Shortcuts") { model.openSettings(keyboardPane) }
        }
    }
    private func fallback(_ kind:ActionKind)->Shortcut {
        switch kind {
        case .missionControl:return Shortcut(keyCode:126,modifiers:["control"])
        case .appExpose:return Shortcut(keyCode:125,modifiers:["control"])
        case .previousDesktop:return Shortcut(keyCode:123,modifiers:["control"])
        case .nextDesktop:return Shortcut(keyCode:124,modifiers:["control"])
        default:return Shortcut(keyCode:103,modifiers:[])
        }
    }
}

struct SetupDiagnosticFields:View {
    @ObservedObject var model:AppModel
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            LabeledContent("Contact stream",value:model.engineStatus)
            LabeledContent("Device ID",value:model.activeDevice.isEmpty ? "None":model.activeDevice)
            LabeledContent("Foreground app",value:"\(model.foregroundName) · \(model.foreground)")
            LabeledContent("Ready mappings",value:String(model.readyMappingCount))
            LabeledContent("Button observation",value:model.buttonObserver ? "Available":"Unavailable")
            LabeledContent("Scroll interception",value:model.scrollFiltering ? "Active":"Unavailable")
            LabeledContent("Detected gesture",value:model.snapshot.gesture)
            LabeledContent("Recognition status",value:model.snapshot.reason.isEmpty ? "Ready":model.snapshot.reason)
            LabeledContent("Last action",value:model.lastAction)
            LabeledContent("Last action time",value:model.lastActionDate?.formatted(date:.omitted,time:.standard) ?? "None")
            LabeledContent("Active sensitivity",value:"X \(model.savedConfig.sensitivity(for:model.foreground).horizontalMM) \(model.savedDistanceUnit) · Y \(model.savedConfig.sensitivity(for:model.foreground).verticalMM) \(model.savedDistanceUnit)")
            Divider()
            Text("Test keyboard delivery independently of gesture detection. App Exposé acts on the foreground app.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Test Mission Control") { model.testSystemAction(.missionControl) }
                Button("Test App Exposé") { model.testSystemAction(.appExpose) }
                Button("Test Show Desktop") { model.testSystemAction(.showDesktop) }
            }.disabled(!model.accessibility)
            Button("Preview Volume Indicator") { model.previewVolumeIndicator() }
            LabeledContent("Volume indicator",value:model.volumeIndicatorVisible ? "Visible":"Hidden")
            Divider()
            Toggle("Enable local in-memory action logging",isOn:$model.config.logging)
            HStack { Button("Copy Diagnostics") { model.copyDiagnostics() }; Button("Clear Log") { model.log=[] }; Button("Reconnect Trackpad") { model.driver.reconnect() } }
            if !model.log.isEmpty { Text(model.log.suffix(50).joined(separator:"\n")).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
            Text("Up to 250 action records stay in memory. Typed content and trackpad coordinates are not written to disk.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
