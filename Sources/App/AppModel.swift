import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct InstalledApplication: Identifiable {
    var id: String; var name: String; var url: URL
}
final class AppModel: ObservableObject {
    static let version = "2.5.0"
    private(set) var settingsVisible = false
    var distanceUnit: String { config.movementScale(for: activeDevice).unit }
    var savedDistanceUnit: String { savedConfig.movementScale(for: activeDevice).unit }
    var wantsDockAndMenu: Bool { settingsVisible || !savedConfig.menuBarOnly }
    func setSettingsVisible(_ visible: Bool) { settingsVisible = visible; refreshActivationPolicy() }
    private func refreshActivationPolicy() { NSApp?.setActivationPolicy(wantsDockAndMenu ? .regular : .accessory) }
    @Published var editing: SettingsDraft
    var config: Configuration { get { editing.config } set { editing.config = newValue } }
    var savedConfig: Configuration { editing.saved }
    var loginEnabled: Bool { get { editing.loginEnabled } set { editing.loginEnabled = newValue } }
    var hasPendingChanges: Bool { editing.hasChanges }
    var canSave: Bool { !editing.externalConflict && (hasPendingChanges || runtimePaused || !FileManager.default.fileExists(atPath: store.url.path) || !configurationIssue.isEmpty) }
    var gestureBlockers: [GestureBlocker] {
        GestureReadiness.blockers(config: savedConfig, app: foreground, device: activeDevice,
            accessibility: accessibility, inputMonitoring: inputMonitoring, runtimePaused: runtimePaused,
            legacyDaemon: !legacyPIDs.isEmpty, configurationError: !configurationIssue.isEmpty, calibrating: calibrationAxis != nil, scrollFiltering: scrollFiltering)
    }
    var readyMappingCount: Int {
        guard gestureBlockers.isEmpty else { return 0 }
        return Gesture.all.filter { g in
            guard g.direction != .tap || (buttonObserver && savedConfig.safety.tapConflictsResolved) else { return false }
            guard g.direction != .click || buttonObserver else { return false }
            return savedConfig.blockedReason(g, mapping: savedConfig.mapping(g, app: foreground), device: activeDevice) == nil
        }.count
    }
    var applicationURL: URL { Bundle.main.bundleURL }
    @Published var runtimePaused = false
    @Published var section = "Dashboard"
    @Published var selectedProfile = ""
    @Published var snapshot = EngineSnapshot()
    @Published var devices: [TrackpadInfo] = []
    @Published var activeDevice = ""
    @Published var engineStatus = "Starting"
    @Published var foreground = ""
    @Published var foregroundName = ""
    @Published var accessibility = false
    @Published var inputMonitoring = false
    @Published var buttonObserver = false
    @Published var scrollFiltering = false
    @Published var volumeIndicatorVisible = false
    var onVolumeFeedback: (VolumeLevel) -> Void = { _ in }
    var onOtherInteraction: () -> Void = {}
    @Published var lastAction = "None"
    @Published var lastActionDate: Date?
    @Published var message = ""
    @Published var configurationIssue = ""
    @Published var log: [String] = []
    @Published var installed: [InstalledApplication] = []
    @Published var calibrationAxis: String?
    @Published var calibrationTravel = 0.0
    @Published var calibrationOffAxis = 0.0
    var calibrationInstruction: String { calibrationTrial?.instruction ?? "" }
    @Published var legacyPIDs: [Int32] = []
    private var calibrationTrial: CalibrationTrial?
    private var observedData: Data?
    private var permissionTimer: Timer?
    private var workspaceToken: NSObjectProtocol?
    let store: ConfigurationStore
    let driver = TrackpadDriver()
    let executor = ActionExecutor()
    init(configurationURL: URL? = nil) {
        store = configurationURL.map(ConfigurationStore.init(url:)) ?? ConfigurationStore()
        let loaded: Configuration
        var loadIssue = ""
        do { loaded = try store.load(persistMigration: false) }
        catch { var fallback = Configuration.defaults; fallback.enabled = false; loaded = fallback; loadIssue = error.localizedDescription }
        let login = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        editing = SettingsDraft(saved: loaded, loginEnabled: login)
        if !loadIssue.isEmpty { configurationIssue = loadIssue; message = "Configuration could not load. Repair it or restore defaults and Save." }
        observedData = try? Data(contentsOf: store.url)
        executor.report = { [weak self] s in self?.record(s) }
        executor.volumeChanged = { [weak self] level in self?.onVolumeFeedback(level) }
        driver.onStatus = { [weak self] s in self?.engineStatus = s }
        driver.onButtonObserver = { [weak self] b in self?.buttonObserver = b }
        driver.onScrollFiltering = { [weak self] enabled in self?.scrollFiltering = enabled }
        driver.onOtherInteraction = { [weak self] in self?.onOtherInteraction() }
        driver.onDevices = { [weak self] list, selected in
            guard let self else { return }; self.devices = list; self.activeDevice = selected
            if selected.isEmpty { self.snapshot = EngineSnapshot() }
        }
        driver.onFrame = { [weak self] snapshot in
            guard let self else { return }; self.snapshot = snapshot
            if self.calibrationAxis != nil {
                self.calibrationTrial?.observe(snapshot.contacts)
                self.calibrationTravel = self.calibrationTrial?.travel ?? 0
                self.calibrationOffAxis = self.calibrationTrial?.crossAxis ?? 0
            }
        }
        driver.onTrigger = { [weak self] trigger, app, generation in
            guard let self else { return }
            let click = trigger.gesture.direction == .click
            let foreground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            let independentMedia = click && [.playPause,.nextTrack,.previousTrack,.volumeUp,.volumeDown,.mute].contains(trigger.mapping.action.kind)
            guard self.savedConfig.enabled, !self.runtimePaused, self.legacyPIDs.isEmpty, self.calibrationAxis == nil,
                  generation == (click ? self.driver.currentClickGeneration : self.driver.currentGeneration),
                  self.accessibility, self.inputMonitoring,
                  foreground == app || (independentMedia && self.savedConfig.mapping(trigger.gesture,app:foreground) == trigger.mapping),
                  self.configurationIssue.isEmpty, self.savedConfig.blockedReason(trigger.gesture, mapping: trigger.mapping, device: self.activeDevice) == nil else { return }
            if trigger.gesture.direction.isSwipe && !self.scrollFiltering { self.record("Custom swipe paused: scroll interception unavailable"); return }
            if ![.volumeUp,.volumeDown].contains(trigger.mapping.action.kind) { self.onOtherInteraction() }
            self.executor.execute(trigger, app: app, config: self.savedConfig)
        }
    }
    func start() {
        foregroundChanged(); checkPermissions(); scanLegacy()
        driver.begin(); apply(); scanApplications()
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.foregroundChanged() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkPermissions(); self?.reloadExternalChanges() }
    }
    func stop() { driver.end(); permissionTimer?.invalidate(); if let workspaceToken { NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken) } }
    func foregroundChanged() {
        foreground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        foregroundName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        apply()
    }
    func apply() {
        executor.cancel()
        var effective = savedConfig
        if runtimePaused || !legacyPIDs.isEmpty || calibrationAxis != nil || !configurationIssue.isEmpty { effective.enabled = false }
        driver.configure(effective, app: foreground)
        refreshActivationPolicy()
    }
    @discardableResult func save() -> Bool {
        do {
            guard !editing.externalConflict else { throw ConfigError.invalid("Settings changed outside the app. Reset to review them before saving.") }
            var candidate = config
            if candidate.selectedDevice.isEmpty { candidate.selectedDevice = activeDevice }
            try persist(candidate, includeLogin: true)
            editing.acceptAll(candidate, loginEnabled: editing.loginEnabled)
            configurationIssue = ""; runtimePaused = false; apply(); checkPermissions()
            return true
        } catch { message = "Settings were not saved: \(error.localizedDescription)"; return false }
    }
    func resetEdits() { editing.reset(); cancelCalibration(); message = "" }
    @discardableResult func saveMapping(_ mapping: Mapping?, gesture: Gesture, profileID: String) -> Bool {
        do {
            let candidate = try editing.savingGesture(gesture, override: mapping, profileID: profileID)
            try persist(candidate, includeLogin: false)
            editing.acceptGesture(candidate, gesture: gesture, override: mapping, profileID: profileID)
            configurationIssue = ""; apply()
            return true
        } catch { message = "Gesture was not saved: \(error.localizedDescription)"; return false }
    }
    private func persist(_ candidate: Configuration, includeLogin: Bool) throws {
        _ = try candidate.validated()
        let currentData = try? Data(contentsOf: store.url)
        guard currentData == observedData else { throw ConfigError.invalid("The configuration file changed outside the app. Wait for it to reload, then Reset to review the changes.") }
        let changeLogin = includeLogin && editing.loginEnabled != editing.savedLoginEnabled
        let originalLogin = editing.savedLoginEnabled
        do {
            if changeLogin { try setLoginService(editing.loginEnabled) }
            if let currentData {
                try currentData.write(to: store.url.deletingLastPathComponent().appendingPathComponent("threefinger.pre-save-\(UUID().uuidString).json"), options: .atomic)
            }
            try store.save(candidate); observedData = try Data(contentsOf: store.url)
        } catch {
            if changeLogin { try? setLoginService(originalLogin) }
            throw error
        }
    }
    private func reloadExternalChanges() {
        guard let data = try? Data(contentsOf: store.url), data != observedData else { return }
        do {
            let updated = try JSONDecoder().decode(Configuration.self, from: data).validated()
            editing.receiveExternal(updated); observedData = data; configurationIssue = ""; apply()
            if editing.externalConflict { message = "Settings changed outside the app. Reset to review the saved settings before continuing." }
        } catch { configurationIssue = error.localizedDescription; message = "Invalid external configuration; actions paused."; observedData = data; apply() }
    }
    func checkPermissions() {
        let ax = AXIsProcessTrusted(), input = CGPreflightListenEventAccess()
        if accessibility != ax || inputMonitoring != input { accessibility = ax; inputMonitoring = input; driver.cancel(); executor.cancel() }
        driver.setPermissions(ax && input)
        editing.observeLogin(SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval)
    }
    func requestPermission(_ permission: PrivacyPermission) {
        if permission == .accessibility {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        } else { _ = CGRequestListenEventAccess() }
        checkPermissions(); openSettings(permission.settingsURL)
    }
    func requestPermissions() { requestPermission(!accessibility ? .accessibility : .inputMonitoring) }
    func testSystemAction(_ kind: ActionKind) {
        guard [.missionControl,.appExpose,.showDesktop].contains(kind), accessibility else { message = "Verify Accessibility before testing system actions."; return }
        let mapping = Mapping(action:Action(kind:kind))
        executor.execute(GestureTrigger(gesture:Gesture(fingers:4,direction:.up),mapping:mapping,count:1),app:NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "",config:savedConfig)
    }
    func previewVolumeIndicator() { onVolumeFeedback(VolumeLevel(value:0.42,muted:false)) }
    func copyApplicationPath() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(applicationURL.path, forType: .string)
    }
    func revealApplication() { NSWorkspace.shared.activateFileViewerSelecting([applicationURL]) }
    func relaunch() {
        guard !hasPendingChanges else { message = "Save or Reset pending edits before relaunching."; return }
        guard let executable = Bundle.main.executableURL, applicationURL.pathExtension == "app" else { message = "Relaunch is available from the installed app."; return }
        let task = Process(); task.executableURL = executable
        task.arguments = ["--wait-for-exit", String(getpid()), "--open-settings"]
        if CommandLine.arguments.contains("--ui-preview") { task.arguments?.append("--ui-preview") }
        do { try task.run(); NSApp?.terminate(nil) }
        catch { message = "Could not relaunch: \(error.localizedDescription)" }
    }
    func openSettings(_ pane: String) { if let url = URL(string: pane) { NSWorkspace.shared.open(url) } }
    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
    func setLogin(_ enabled: Bool) { loginEnabled = enabled }
    private func setLoginService(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        if SMAppService.mainApp.status == .requiresApproval { message = "Approve EvenBetterTouchTool in macOS Login Items to finish enabling startup." }
    }
    func emergencyDisable() { runtimePaused = true; config.enabled = false; driver.cancel(); executor.cancel(); apply(); record("Emergency pause — settings unchanged on disk") }
    func toggleFromMenu() {
        if runtimePaused { runtimePaused = false; config.enabled = savedConfig.enabled; apply() }
        else if savedConfig.enabled { emergencyDisable() }
        else { config.enabled = true; message = "Click Save in Settings to enable gestures." }
    }
    func record(_ text: String) {
        lastAction = text; lastActionDate = Date()
        if savedConfig.logging { log.append("\(Date().formatted(date: .omitted, time: .standard))  \(text)"); if log.count > 250 { log.removeFirst(log.count-250) } }
    }
    func mapping(_ gesture: Gesture) -> Mapping { editing.mapping(gesture, profileID: selectedProfile) }
    func rowEnabled(_ fingers: Int) -> Bool { editing.rowEnabled(fingers, profileID: selectedProfile) }
    func toggleRow(_ fingers: Int) { editing.toggleRow(fingers, profileID: selectedProfile) }
    func swapRows(_ direction: Direction) { editing.swapRows(direction:direction,profileID:selectedProfile) }
    func addProfile(id: String, name: String) {
        guard !config.profiles.contains(where: { $0.bundleID == id }) else { selectedProfile = id; return }
        config.profiles.append(AppProfile(bundleID: id, name: name)); selectedProfile = id
    }
    func chooseApplication(_ completion: @escaping (String, String) -> Void) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.canChooseDirectories = false
        panel.begin { result in if result == .OK, let url = panel.url, let b = Bundle(url: url), let id = b.bundleIdentifier { completion(id, b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent) } }
    }
    func scanApplications() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var apps: [String: InstalledApplication] = [:]
            for root in ["/Applications", "/System/Applications", NSHomeDirectory()+"/Applications"] {
                guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants, .skipsHiddenFiles]) else { continue }
                for case let url as URL in enumerator where url.pathExtension == "app" {
                    guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                    apps[id] = InstalledApplication(id: id, name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent, url: url)
                }
            }
            let result = apps.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async { self?.installed = result }
        }
    }
    func exportSettings() {
        let exported = savedConfig
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "EvenBetterTouchTool-profile.json"
        panel.begin { [weak self] result in guard result == .OK, let url = panel.url, let self else { return }; do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(exported).write(to: url, options: .atomic) } catch { self.message = error.localizedDescription } }
    }
    func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url, let self else { return }
            do { try self.stageImport(from: url) }
            catch { self.message = error.localizedDescription }
        }
    }
    func stageImport(from url: URL) throws {
        var imported = try store.readImport(url)
        imported.selectedDevice = activeDevice
        config = imported; message = "Imported settings are pending. Click Save to apply them."
    }
    func restoreDefaults() {
        config = .defaults; config.selectedDevice = activeDevice
    }
    func confirmCalibrationDimensions() {
        guard !activeDevice.isEmpty, var calibration = config.calibrations[activeDevice], calibration.dimensionsValid else {
            message = "Enter both measured dimensions between 20 and 300 mm, or keep using relative sensitivity."
            return
        }
        calibration.confirmed = true; config.calibrations[activeDevice] = calibration
    }
    func useRelativeSensitivity() { config.calibrations.removeValue(forKey: activeDevice) }
    func startCalibration(_ axis: String) { calibrationTrial = CalibrationTrial(horizontal: axis == "X", waitForLift: true); calibrationTravel = 0; calibrationOffAxis = 0; calibrationAxis = axis; apply() }
    func finishCalibration(distance: Double) {
        guard let axis = calibrationAxis, let trial = calibrationTrial else { return }
        let full: Double
        do { full = try trial.fullAxisMM(measuredDistance: distance) }
        catch { message = error.localizedDescription; return }
        var c = config.calibrations[activeDevice] ?? Calibration()
        if axis == "X" { c.widthMM = full } else { c.heightMM = full }
        c.confirmed = c.widthMM >= 20 && c.heightMM >= 20
        config.calibrations[activeDevice] = c; calibrationAxis = nil; apply()
    }
    func cancelCalibration() { calibrationTrial = nil; calibrationAxis = nil; apply() }
    var diagnostics: String {
        """
        EvenBetterTouchTool \(Self.version) • \(ProcessInfo.processInfo.operatingSystemVersionString)
        App path: \(applicationURL.path)
        Blockers: \(gestureBlockers.map(\.title).joined(separator: "; "))
        Configuration issue: \(configurationIssue)
        Engine: \(engineStatus) • Enabled: \(savedConfig.enabled && !runtimePaused)
        Device: \(activeDevice) • Devices: \(devices.count)
        Accessibility: \(accessibility) • Input Monitoring: \(inputMonitoring) • Button observation: \(buttonObserver) • Scroll filtering: \(scrollFiltering)
        App: \(foregroundName) (\(foreground))
        Movement scale: \(savedConfig.movementScale(for: activeDevice).title)
        Fingers: \(snapshot.fingers) • dx: \(snapshot.dxMM) \(savedDistanceUnit) • dy: \(snapshot.dyMM) \(savedDistanceUnit)
        Contacts: \(snapshot.contacts)
        Gesture: \(snapshot.gesture) • Reason: \(snapshot.reason)
        Action: \(lastAction) • Last action: \(lastActionDate?.description ?? "None")
        Sensitivity: \(savedConfig.sensitivity(for: foreground))
        Calibration: \(String(describing: savedConfig.calibrations[activeDevice]))
        Legacy daemons: \(legacyPIDs)
        """
    }
    func copyDiagnostics() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(diagnostics, forType: .string) }
    func scanLegacy() {
        let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/bin/ps"); process.arguments = ["-U", String(getuid()), "-o", "pid=,comm="]; process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do {
            try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            legacyPIDs = (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").compactMap { line in
                let p = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard p.count == 2, URL(fileURLWithPath: String(p[1])).lastPathComponent == "threefinger" else { return nil }; return Int32(p[0])
            }
            if !legacyPIDs.isEmpty { message = "Original threefinger daemon is running. Run the local install.sh to migrate safely; custom actions are paused." }
            apply()
        } catch { message = "Could not check for the legacy daemon; run install.sh before enabling gestures"; runtimePaused = true; apply() }
    }
}
