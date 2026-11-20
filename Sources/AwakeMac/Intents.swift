import AppIntents
import Foundation

/// Shortcuts.app / Siri / Spotlight actions.
enum AwakeModeOption: String, AppEnum {
    case off, light, lid

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Awake Mac Mode"
    static var caseDisplayRepresentations: [AwakeModeOption: DisplayRepresentation] = [
        .off: "Off", .light: "Light", .lid: "Lid closed",
    ]
}

struct SetAwakeModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Awake Mac Mode"
    static var description = IntentDescription("Turns Awake Mac off, to Light mode, or to Lid-closed mode, optionally for a number of minutes.")

    @Parameter(title: "Mode")
    var mode: AwakeModeOption

    @Parameter(title: "Minutes (0 = use default)", default: 0)
    var minutes: Int

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let m = AwakeMode(rawValue: mode.rawValue) ?? .off
        AwakeController.shared.select(m, minutes: minutes > 0 ? minutes : nil)
        return .result()
    }
}

struct ToggleAwakeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Awake Mac"
    static var description = IntentDescription("Turns the last used Awake Mac mode on or off.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        AwakeController.shared.toggle()
        return .result()
    }
}

struct AwakeMacShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ToggleAwakeIntent(), phrases: ["Toggle \(.applicationName)"],
                    shortTitle: "Toggle", systemImageName: "sun.max")
        AppShortcut(intent: SetAwakeModeIntent(), phrases: ["Set \(.applicationName) mode"],
                    shortTitle: "Set Mode", systemImageName: "laptopcomputer")
    }
}
