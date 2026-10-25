import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct InstalledApplication: Identifiable {
    var id: String; var name: String; var url: URL
}
final class AppModel: ObservableObject {
    static let version = "2.0.0"
    @Published var config: Configuration {
        didSet {
            guard !loading else { return }
            dirty = true
            apply(); pendingSave?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.save() }; pendingSave = item
            DispatchQueue.main.asyncAfter(deadline: .now()+0.2, execute: item)
        }
    }
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
    @Published var loginEnabled = false
    @Published var calibrationAxis: String?
    @Published var calibrationTravel = 0.0
    @Published var calibrationOffAxis = 0.0
    @Published var legacyPIDs: [Int32] = []
    private var calibrationTrial: CalibrationTrial?
    private var loading = false
    private var dirty = false
    private var pendingSave: DispatchWorkItem?
    private var observedData: Data?
    private var permissionTimer: Timer?
    private var workspaceToken: NSObjectProtocol?
    let store: ConfigurationStore
    let driver = TrackpadDriver()
    let executor = ActionExecutor()
    init(configurationURL: URL? = nil) {
        store = configurationURL.map(ConfigurationStore.init(url:)) ?? ConfigurationStore()
        do { config = try store.load() }
        catch { config = .defaults; config.enabled = false; configurationIssue = error.localizedDescription; message = "Configuration was preserved but could not load: \(error.localizedDescription). Repair it or restore defaults to resume." }
        observedData = try? Data(contentsOf: store.url)
        executor.report = { [weak self] s in self?.record(s) }
        driver.onStatus = { [weak self] s in self?.engineStatus = s }
        driver.onButtonObserver = { [weak self] b in self?.buttonObserver = b }
        driver.onDevices = { [weak self] list, selected in
            guard let self else { return }; self.devices = list; self.activeDevice = selected
            if selected.isEmpty { self.snapshot = EngineSnapshot() }
            if self.config.selectedDevice.isEmpty, !selected.isEmpty { self.config.selectedDevice = selected }
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
            guard let self, self.config.enabled, self.legacyPIDs.isEmpty, self.calibrationAxis == nil, generation == self.driver.currentGeneration,
                  self.accessibility, self.inputMonitoring, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app,
                  self.configurationIssue.isEmpty, self.config.blockedReason(trigger.gesture, mapping: trigger.mapping, device: self.activeDevice) == nil else { return }
            self.executor.execute(trigger, app: app, config: self.config)
        }
    }
    func start() {
        foregroundChanged(); checkPermissions(); scanLegacy()
        driver.begin(); apply(); scanApplications()
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.foregroundChanged() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkPermissions(); self?.reloadExternalChanges() }
    }
    func stop() { save(); driver.end(); permissionTimer?.invalidate(); if let workspaceToken { NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken) } }
    func foregroundChanged() {
        foreground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        foregroundName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        apply()
    }
    func apply() {
        executor.cancel()
        var effective = config
        if !legacyPIDs.isEmpty || calibrationAxis != nil || !configurationIssue.isEmpty { effective.enabled = false }
        driver.configure(effective, app: foreground)
        NSApp.setActivationPolicy(config.menuBarOnly ? .accessory : .regular)
    }
    func save() {
        pendingSave = nil
        guard dirty else { return }
        do {
            // Preserve malformed files too, before the first intentional GUI edit.
            if let data = try? Data(contentsOf: store.url), (try? JSONDecoder().decode(Configuration.self, from: data)) == nil {
                try data.write(to: store.url.deletingLastPathComponent().appendingPathComponent("threefinger.unreadable-\(UUID().uuidString).json"), options: .atomic)
            }
            let wasPaused = !configurationIssue.isEmpty
            try store.save(config); observedData = try? Data(contentsOf: store.url); dirty = false; configurationIssue = ""
            if wasPaused { apply() }
        } catch { configurationIssue = error.localizedDescription; message = "Settings could not be saved: \(error.localizedDescription)"; apply() }
    }
    private func reloadExternalChanges() {
        guard pendingSave?.isCancelled != false, let data = try? Data(contentsOf: store.url), data != observedData else { return }
        do {
            let updated = try JSONDecoder().decode(Configuration.self, from: data).validated()
            loading = true; config = updated; loading = false; observedData = data; configurationIssue = ""; apply()
        } catch { configurationIssue = error.localizedDescription; message = "External configuration change rejected; actions paused: \(error.localizedDescription)"; observedData = data; apply() }
    }
    func checkPermissions() {
        let ax = AXIsProcessTrusted(), input = CGPreflightListenEventAccess()
        if accessibility != ax || inputMonitoring != input { accessibility = ax; inputMonitoring = input; driver.cancel(); executor.cancel() }
        loginEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
    }
    func requestPermissions() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue():true] as CFDictionary)
        _ = CGRequestListenEventAccess(); checkPermissions()
    }
    func openSettings(_ pane: String) { if let url = URL(string: pane) { NSWorkspace.shared.open(url) } }
    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; checkPermissions(); if SMAppService.mainApp.status == .requiresApproval { message = "Approve EvenBetterTouchTool in System Settings → General → Login Items to finish enabling login startup." } }
        catch { message = "Login setting: \(error.localizedDescription). Install the app in Applications first." }
    }
    func emergencyDisable() { config.enabled = false; driver.cancel(); executor.cancel(); record("Emergency global disable") }
    func record(_ text: String) {
        lastAction = text; lastActionDate = Date()
        if config.logging { log.append("\(Date().formatted(date: .omitted, time: .standard))  \(text)"); if log.count > 250 { log.removeFirst(log.count-250) } }
    }
    func mapping(_ gesture: Gesture) -> Mapping {
        if selectedProfile.isEmpty { return config.mappings[gesture.id] ?? Mapping(enabled: false) }
        return config.profiles.first { $0.bundleID == selectedProfile }?.mappings[gesture.id] ?? config.mappings[gesture.id] ?? Mapping(enabled: false)
    }
    func setMapping(_ mapping: Mapping, gesture: Gesture) {
        if selectedProfile.isEmpty { config.mappings[gesture.id] = mapping }
        else if let i = config.profiles.firstIndex(where: { $0.bundleID == selectedProfile }) { config.profiles[i].mappings[gesture.id] = mapping }
    }
    func restoreMapping(_ g: Gesture) {
        if selectedProfile.isEmpty { config.mappings[g.id] = Configuration.defaults.mappings[g.id] }
        else if let i = config.profiles.firstIndex(where: { $0.bundleID == selectedProfile }) {
            config.profiles[i].mappings[g.id] = Configuration.defaultProfile(selectedProfile, name: config.profiles[i].name).mappings[g.id]
        }
    }
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
        save(); let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "EvenBetterTouchTool-profile.json"
        panel.begin { [weak self] result in guard result == .OK, let url = panel.url, let self else { return }; do { try Data(contentsOf: self.store.url).write(to: url, options: .atomic) } catch { self.message = error.localizedDescription } }
    }
    func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url, let self else { return }
            do {
                var imported = try self.store.importFile(url)
                // Consent and dimensions are local hardware state, never trusted from imports.
                imported.safety = Safety(); imported.calibrations = [:]; imported.selectedDevice = self.activeDevice
                self.config = imported; self.save()
            } catch { self.message = error.localizedDescription }
        }
    }
    func restoreDefaults() {
        if let data = try? Data(contentsOf: store.url) { try? data.write(to: store.url.deletingLastPathComponent().appendingPathComponent("threefinger.pre-reset-\(UUID().uuidString).json"), options: .atomic) }
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
        Engine: \(engineStatus) • Enabled: \(config.enabled)
        Device: \(activeDevice) • Devices: \(devices.count)
        Accessibility: \(accessibility) • Input Monitoring: \(inputMonitoring) • Button observation: \(buttonObserver)
        App: \(foregroundName) (\(foreground))
        Fingers: \(snapshot.fingers) • dx: \(snapshot.dxMM) mm • dy: \(snapshot.dyMM) mm
        Contacts: \(snapshot.contacts)
        Gesture: \(snapshot.gesture) • Reason: \(snapshot.reason)
        Action: \(lastAction) • Last action: \(lastActionDate?.description ?? "None")
        Sensitivity: \(config.sensitivity(for: foreground))
        Calibration: \(String(describing: config.calibrations[activeDevice]))
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
        } catch { message = "Could not check for the legacy daemon; run install.sh before enabling gestures"; config.enabled = false }
    }
}
