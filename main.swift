import AppKit
import ServiceManagement

if CommandLine.arguments.contains("--quit-running") {
    var failed = false
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: "org.evenbettertouchtool.app") where app.processIdentifier != getpid() {
        if !app.terminate() { failed = true }
    }
    exit(failed ? 1 : 0)
}
if CommandLine.arguments.contains("--unregister-login") {
    do { try SMAppService.mainApp.unregister(); exit(0) }
    catch { if SMAppService.mainApp.status == .notRegistered || SMAppService.mainApp.status == .notFound { exit(0) }; fputs("Login item removal failed: \(error.localizedDescription). Disable it in System Settings → General → Login Items, then retry.\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--version") { print("EvenBetterTouchTool \(AppModel.version)"); exit(0) }
if CommandLine.arguments.contains("--reinstall") { fputs("Upstream reinstall is disabled. Use this project's local install.sh.\n", stderr); exit(2) }
if CommandLine.arguments.contains("--help") {
    print("EvenBetterTouchTool — menu bar trackpad customizer\nOpen EvenBetterTouchTool.app. Local install: ./install.sh\nEmergency disable: Control–Option–Command–Escape\nSettings: ~/.config/threefinger.json\nOptions: --version, --help, --smoke-test, --ui-preview")
    exit(0)
}
if CommandLine.arguments.contains("--smoke-test") {
    do { _ = try Configuration.defaults.validated(); print("EvenBetterTouchTool \(AppModel.version): configuration and AppKit loaded; architecture \(ProcessInfo.processInfo.machineArchitecture)"); exit(0) }
    catch { fputs("\(error)\n", stderr); exit(1) }
}
extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
