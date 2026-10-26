import Foundation

enum PrivacyPermission: String, CaseIterable, Identifiable {
    case accessibility, inputMonitoring
    var id: String { rawValue }
    var title: String { self == .accessibility ? "Accessibility" : "Input Monitoring" }
    var settingsURL: String {
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?" + (self == .accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent")
    }
}
enum GestureBlocker: String, Identifiable {
    case disabled, emergencyPause, accessibility, inputMonitoring, trackpad, nativeSetup, calibration, configuration, legacyDaemon, calibrating, noMappings, scrollFiltering
    var id: String { rawValue }
    var title: String {
        switch self {
        case .disabled: return "Enable gestures and click Save"
        case .emergencyPause: return "Emergency pause is active"
        case .accessibility: return "Verify Accessibility permission"
        case .inputMonitoring: return "Add the app to Input Monitoring"
        case .trackpad: return "Connect or select a trackpad"
        case .nativeSetup: return "Complete native gesture setup and click Save"
        case .calibration: return "Calibrate the trackpad and click Save"
        case .configuration: return "Repair the configuration error"
        case .legacyDaemon: return "Stop the original threefinger daemon"
        case .calibrating: return "Finish the calibration measurement"
        case .noMappings: return "No custom gestures are enabled for this app"
        case .scrollFiltering: return "Custom swipe scroll interception is unavailable"
        }
    }
}
enum GestureReadiness {
    static func blockers(config: Configuration, app: String, device: String, accessibility: Bool, inputMonitoring: Bool,
                         runtimePaused: Bool = false, legacyDaemon: Bool = false, configurationError: Bool = false, calibrating: Bool = false, scrollFiltering: Bool = true) -> [GestureBlocker] {
        var result: [GestureBlocker] = []
        if !config.enabled { result.append(.disabled) }
        if runtimePaused { result.append(.emergencyPause) }
        if !accessibility { result.append(.accessibility) }
        if !inputMonitoring { result.append(.inputMonitoring) }
        if device.isEmpty { result.append(.trackpad) }
        if !config.safety.nativeConflictsResolved { result.append(.nativeSetup) }
        if configurationError { result.append(.configuration) }
        if legacyDaemon { result.append(.legacyDaemon) }
        if calibrating { result.append(.calibrating) }
        if !scrollFiltering && Gesture.all.contains(where: { $0.direction.isSwipe && config.blockedReason($0,mapping:config.mapping($0,app:app),device:device) == nil }) { result.append(.scrollFiltering) }
        if !Gesture.all.contains(where: {
            let m = config.mapping($0, app: app)
            return m.enabled && ![.none, .native, .notificationCenter].contains(m.action.kind)
        }) { result.append(.noMappings) }
        return result
    }
}
