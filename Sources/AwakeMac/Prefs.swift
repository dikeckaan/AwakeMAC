import Combine
import Foundation

/// All user preferences, persisted in UserDefaults and observable from SwiftUI.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    // General
    @Published var duration: AwakeDuration { didSet { d.set(duration.rawValue, forKey: "duration") } }
    @Published var rememberMode: Bool { didSet { d.set(rememberMode, forKey: "rememberMode") } }
    @Published var showTimeInMenuBar: Bool { didSet { d.set(showTimeInMenuBar, forKey: "showTimeInMenuBar") } }
    @Published var hotkeyEnabled: Bool { didSet { d.set(hotkeyEnabled, forKey: "hotkeyEnabled") } }
    @Published var keepDisplayOn: Bool { didSet { d.set(keepDisplayOn, forKey: "keepDisplayOn") } }
    @Published var checkUpdates: Bool { didSet { d.set(checkUpdates, forKey: "checkUpdates") } }
    @Published var lastMode: AwakeMode { didSet { d.set(lastMode.rawValue, forKey: "lastMode") } }
    @Published var onboardingDone: Bool { didSet { d.set(onboardingDone, forKey: "onboardingDone") } }

    // Safety
    @Published var batteryThreshold: Int { didSet { d.set(batteryThreshold, forKey: "batteryThreshold") } }
    @Published var lidOnlyOnAC: Bool { didSet { d.set(lidOnlyOnAC, forKey: "lidOnlyOnAC") } }
    @Published var lockOnLidClose: Bool { didSet { d.set(lockOnLidClose, forKey: "lockOnLidClose") } }
    @Published var heatWarning: Bool { didSet { d.set(heatWarning, forKey: "heatWarning") } }
    @Published var expiryWarning: Bool { didSet { d.set(expiryWarning, forKey: "expiryWarning") } }

    // Triggers
    @Published var triggersEnabled: Bool { didSet { d.set(triggersEnabled, forKey: "triggersEnabled") } }
    @Published var triggerMode: AwakeMode { didSet { d.set(triggerMode.rawValue, forKey: "triggerMode") } }
    @Published var triggerApps: [String] { didSet { d.set(triggerApps, forKey: "triggerApps") } }
    @Published var triggerProcesses: String { didSet { d.set(triggerProcesses, forKey: "triggerProcesses") } }
    @Published var triggerNetworkKBps: Int { didSet { d.set(triggerNetworkKBps, forKey: "triggerNetworkKBps") } }
    @Published var triggerOnAC: Bool { didSet { d.set(triggerOnAC, forKey: "triggerOnAC") } }
    @Published var triggerExternalDisplay: Bool { didSet { d.set(triggerExternalDisplay, forKey: "triggerExternalDisplay") } }
    @Published var scheduleEnabled: Bool { didSet { d.set(scheduleEnabled, forKey: "scheduleEnabled") } }
    @Published var scheduleStart: Int { didSet { d.set(scheduleStart, forKey: "scheduleStart") } } // minutes after midnight
    @Published var scheduleEnd: Int { didSet { d.set(scheduleEnd, forKey: "scheduleEnd") } }

    static let thresholdChoices = [0, 10, 15, 20, 30, 40]
    static let networkChoices = [0, 50, 200, 1000, 5000]

    var processNames: [String] {
        triggerProcesses.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    var scheduleWindow: DailyWindow { DailyWindow(start: scheduleStart, end: scheduleEnd) }

    init() {
        d.register(defaults: [
            "duration": AwakeDuration.forever.rawValue, "batteryThreshold": 20,
            "showTimeInMenuBar": true, "hotkeyEnabled": true, "checkUpdates": true,
            "lastMode": AwakeMode.lid.rawValue, "lockOnLidClose": true, "heatWarning": true,
            "expiryWarning": true, "triggerMode": AwakeMode.light.rawValue,
            "triggerProcesses": "ffmpeg, rsync, xcodebuild", "scheduleStart": 60, "scheduleEnd": 420,
        ])
        duration = AwakeDuration(rawValue: d.integer(forKey: "duration")) ?? .forever
        rememberMode = d.bool(forKey: "rememberMode")
        showTimeInMenuBar = d.bool(forKey: "showTimeInMenuBar")
        hotkeyEnabled = d.bool(forKey: "hotkeyEnabled")
        keepDisplayOn = d.bool(forKey: "keepDisplayOn")
        checkUpdates = d.bool(forKey: "checkUpdates")
        lastMode = AwakeMode(rawValue: d.string(forKey: "lastMode") ?? "") ?? .lid
        onboardingDone = d.bool(forKey: "onboardingDone")
        batteryThreshold = d.integer(forKey: "batteryThreshold")
        lidOnlyOnAC = d.bool(forKey: "lidOnlyOnAC")
        lockOnLidClose = d.bool(forKey: "lockOnLidClose")
        heatWarning = d.bool(forKey: "heatWarning")
        expiryWarning = d.bool(forKey: "expiryWarning")
        triggersEnabled = d.bool(forKey: "triggersEnabled")
        triggerMode = AwakeMode(rawValue: d.string(forKey: "triggerMode") ?? "") ?? .light
        triggerApps = d.stringArray(forKey: "triggerApps") ?? []
        triggerProcesses = d.string(forKey: "triggerProcesses") ?? ""
        triggerNetworkKBps = d.integer(forKey: "triggerNetworkKBps")
        triggerOnAC = d.bool(forKey: "triggerOnAC")
        triggerExternalDisplay = d.bool(forKey: "triggerExternalDisplay")
        scheduleEnabled = d.bool(forKey: "scheduleEnabled")
        scheduleStart = d.integer(forKey: "scheduleStart")
        scheduleEnd = d.integer(forKey: "scheduleEnd")
    }
}
