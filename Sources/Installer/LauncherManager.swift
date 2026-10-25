import Foundation

enum LauncherError: LocalizedError {
    case invalidApplication, noAvailableLocation([String])
    var errorDescription: String? {
        switch self {
        case .invalidApplication: return "The target is not an installed EvenBetterTouchTool app."
        case .noAvailableLocation(let errors): return "Could not create a launch shortcut: " + errors.joined(separator: "; ")
        }
    }
}
enum LauncherState: String { case missing, managed, unrelated, application }
/// Filesystem-only Finder aliases. No Apple Events, permissions, or compiler needed at install time.
struct LauncherManager {
    static let bundleID = "org.evenbettertouchtool.app"
    private let files = FileManager.default
    private func canonical(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }
    private func exists(_ url: URL) -> Bool { (try? files.attributesOfItem(atPath: url.path)) != nil }
    func resolveApplication(_ url: URL) throws -> URL {
        var resolved = canonical(url)
        if (try? resolved.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true {
            resolved = try URL(resolvingAliasFileAt: resolved, options: [.withoutUI, .withoutMounting])
        }
        resolved = canonical(resolved)
        guard Bundle(url: resolved)?.bundleIdentifier == Self.bundleID,
              (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw LauncherError.invalidApplication }
        return resolved
    }
    func state(app: URL, shortcut: URL) -> LauncherState {
        if canonical(shortcut) == canonical(app) && !((try? shortcut.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true) { return .application }
        guard exists(shortcut) else { return .missing }
        if (try? shortcut.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return canonical(shortcut) == canonical(app) ? .managed : .unrelated
        }
        guard (try? shortcut.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true,
              let resolved = try? URL(resolvingAliasFileAt: shortcut, options: [.withoutUI, .withoutMounting]) else { return .unrelated }
        return canonical(resolved) == canonical(app) ? .managed : .unrelated
    }
    @discardableResult func create(app input: URL, locations: [URL]) throws -> URL {
        let app = try resolveApplication(input)
        var errors: [String] = []
        for location in locations {
            switch state(app: app, shortcut: location) {
            case .application, .managed: return location
            case .unrelated: errors.append("An unrelated item already exists at \(location.path)"); continue
            case .missing: break
            }
            do {
                // The shell supplies existing standard folders. Never manufacture
                // a missing shared Applications folder or silently replace a file.
                guard files.fileExists(atPath: location.deletingLastPathComponent().path) else {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
                }
                let temporary = location.deletingLastPathComponent().appendingPathComponent(".EvenBetterTouchTool-shortcut-"+UUID().uuidString)
                defer { try? files.removeItem(at: temporary) }
                let bookmark = try app.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
                try URL.writeBookmarkData(bookmark, to: temporary)
                // moveItem fails on a concurrent destination, protecting unrelated items.
                try files.moveItem(at: temporary, to: location)
                return location
            } catch { errors.append("\(location.path): \(error.localizedDescription)") }
        }
        throw LauncherError.noAvailableLocation(errors)
    }
    @discardableResult func remove(app input: URL, locations: [URL]) throws -> [URL] {
        let app = try resolveApplication(input)
        var removed: [URL] = []
        for location in locations where state(app: app, shortcut: location) == .managed {
            try files.removeItem(at: location); removed.append(location)
        }
        return removed
    }
}
