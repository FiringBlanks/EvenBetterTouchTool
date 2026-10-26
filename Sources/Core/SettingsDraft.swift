import Foundation

/// Pending UI edits never mutate the engine's saved configuration.
struct SettingsDraft: Equatable {
    private(set) var saved: Configuration
    var config: Configuration
    private(set) var savedLoginEnabled: Bool
    var loginEnabled: Bool
    private(set) var externalConflict = false
    init(saved: Configuration, loginEnabled: Bool = false) {
        self.saved = saved; config = saved
        savedLoginEnabled = loginEnabled; self.loginEnabled = loginEnabled
    }
    var hasChanges: Bool { config != saved || loginEnabled != savedLoginEnabled }
    mutating func reset() { config = saved; loginEnabled = savedLoginEnabled; externalConflict = false }
    mutating func acceptAll(_ config: Configuration, loginEnabled: Bool) {
        saved = config; self.config = config
        savedLoginEnabled = loginEnabled; self.loginEnabled = loginEnabled; externalConflict = false
    }
    mutating func observeLogin(_ enabled: Bool) {
        if loginEnabled == savedLoginEnabled { loginEnabled = enabled }
        savedLoginEnabled = enabled
    }
    mutating func receiveExternal(_ config: Configuration) {
        let pending = hasChanges
        saved = config
        if pending { externalConflict = true } else { self.config = config }
    }
    func mapping(_ gesture: Gesture, profileID: String) -> Mapping {
        override(gesture, profileID: profileID) ?? config.mappings[gesture.id] ?? Mapping(enabled: false)
    }
    func override(_ gesture: Gesture, profileID: String) -> Mapping? {
        if profileID.isEmpty { return config.mappings[gesture.id] }
        return config.profiles.first { $0.bundleID == profileID }?.mappings[gesture.id]
    }
    /// A gesture's Save commits only this cell, leaving unrelated drafts pending.
    func savingGesture(_ gesture: Gesture, override: Mapping?, profileID: String) throws -> Configuration {
        guard !externalConflict else { throw ConfigError.invalid("Settings changed outside the app. Reset to review the latest saved settings first.") }
        var result = saved
        if profileID.isEmpty { result.mappings[gesture.id] = override }
        else {
            if !result.profiles.contains(where: { $0.bundleID == profileID }) {
                guard let draftProfile = config.profiles.first(where: { $0.bundleID == profileID }) else { throw ConfigError.invalid("Application profile no longer exists") }
                result.profiles.append(AppProfile(bundleID: profileID, name: draftProfile.name))
            }
            let i = result.profiles.firstIndex { $0.bundleID == profileID }!
            result.profiles[i].mappings[gesture.id] = override
        }
        return try result.validated()
    }
    mutating func acceptGesture(_ saved: Configuration, gesture: Gesture, override: Mapping?, profileID: String) {
        self.saved = saved
        if profileID.isEmpty { config.mappings[gesture.id] = override }
        else if let i = config.profiles.firstIndex(where: { $0.bundleID == profileID }) { config.profiles[i].mappings[gesture.id] = override }
    }
    func rowEnabled(_ fingers: Int, profileID: String) -> Bool {
        let key = String(fingers)
        let profile = config.profiles.first { $0.bundleID == profileID }
        return profile?.rowEnabled?[key] ?? config.rowEnabled?[key] ?? true
    }
    mutating func toggleRow(_ fingers: Int, profileID: String) {
        let value = !rowEnabled(fingers, profileID: profileID), key = String(fingers)
        if profileID.isEmpty { if config.rowEnabled == nil { config.rowEnabled = [:] }; config.rowEnabled?[key] = value }
        else if let i = config.profiles.firstIndex(where: { $0.bundleID == profileID }) {
            if config.profiles[i].rowEnabled == nil { config.profiles[i].rowEnabled = [:] }
            config.profiles[i].rowEnabled?[key] = value
        }
    }
    /// Swap complete cell settings. App profiles swap their effective values,
    /// creating overrides only where the result differs from the global cell.
    /// Row enabled switches remain attached to their finger counts.
    mutating func swapRows(direction: Direction, profileID: String) {
        let three = Gesture(fingers:3,direction:direction), four = Gesture(fingers:4,direction:direction)
        if profileID.isEmpty {
            let first = config.mappings[three.id], second = config.mappings[four.id]
            config.mappings[three.id] = second; config.mappings[four.id] = first
        } else if let i = config.profiles.firstIndex(where: { $0.bundleID == profileID }) {
            let first = mapping(three,profileID:profileID), second = mapping(four,profileID:profileID)
            let globalThree = config.mappings[three.id] ?? Mapping(enabled:false)
            let globalFour = config.mappings[four.id] ?? Mapping(enabled:false)
            config.profiles[i].mappings[three.id] = second == globalThree ? nil : second
            config.profiles[i].mappings[four.id] = first == globalFour ? nil : first
        }
    }
}
