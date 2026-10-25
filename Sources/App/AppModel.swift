import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct InstalledApplication: Identifiable {
    var id: String; var name: String; var url: URL
}
final class AppModel: ObservableObject {
    static let version = "2.1.0"
    @Published var editing: SettingsDraft
    var config: Configuration { get { editing.config } set { editing.config = newValue } }
    var savedConfig: Configuration { editing.saved }
    var loginEnabled: Bool { get { editing.loginEnabled } set { editing.loginEnabled = newValue } }
    var hasPendingChanges: Bool { editing.hasChanges }
    var canSave: Bool { !editing.externalConflict && (hasPendingChanges || runtimePaused || !FileManager.default.fileExists(atPath: store.url.path) || !configurationIssue.isEmpty) }
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
    @Published var lastAction = "None"
    @Published var lastActionDate: Date?
    @Published var message = ""
    @Published var configurationIssue = ""
    @Published var log: [String] = []
    @Published var installed: [InstalledApplication] = []
    @Published var calibrationAxis: String?
    @Published var calibrationTravel = 0.0
    @Published var calibrationOffAxis = 0.0
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
        driver.onStatus = { [weak self] s in self?.engineStatus = s }
        driver.onButtonObserver = { [weak self] b in self?.buttonObserver = b }
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
            guard let self, self.savedConfig.enabled, !self.runtimePaused, self.legacyPIDs.isEmpty, self.calibrationAxis == nil, generation == self.driver.currentGeneration,
                  self.accessibility, self.inputMonitoring, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app,
                  self.configurationIssue.isEmpty, self.savedConfig.blockedReason(trigger.gesture, mapping: trigger.mapping, device: self.activeDevice) == nil else { return }
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
        if let app = NSApp { app.setActivationPolicy(savedConfig.menuBarOnly ? .accessory : .regular) }
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
        editing.observeLogin(SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval)
    }
    func requestPermissions() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue():true] as CFDictionary)
        _ = CGRequestListenEventAccess(); checkPermissions()
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
    func startCalibration(_ axis: String) { calibrationTrial = CalibrationTrial(horizontal: axis == "X"); calibrationTravel = 0; calibrationOffAxis = 0; calibrationAxis = axis; apply() }
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
        Configuration issue: \(configurationIssue)
        Engine: \(engineStatus) • Enabled: \(savedConfig.enabled && !runtimePaused)
        Device: \(activeDevice) • Devices: \(devices.count)
        Accessibility: \(accessibility) • Input Monitoring: \(inputMonitoring) • Button observation: \(buttonObserver)
        App: \(foregroundName) (\(foreground))
        Fingers: \(snapshot.fingers) • dx: \(snapshot.dxMM) mm • dy: \(snapshot.dyMM) mm
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
