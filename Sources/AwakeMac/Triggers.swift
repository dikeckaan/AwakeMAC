import AppKit
import Combine
import Foundation

/// Watches the configured conditions and reports why the Mac should stay awake
/// automatically (or `nil`). Event driven where macOS offers events; processes and
/// network traffic are sampled every 30 s, and only while such a trigger is set.
@MainActor
final class TriggerMonitor {
    private let prefs = Prefs.shared
    private var onChange: ((String?) -> Void)?
    private var sampleTimer: Timer?
    private var scheduleTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var lastBytes: UInt64?
    private var lastSampleDate: Date?
    private var networkActive = false
    private(set) var currentReason: String?

    func start(_ onChange: @escaping (String?) -> Void) {
        self.onChange = onChange
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.evaluate() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.evaluate() } })

        // Re-configure whenever a trigger preference changes.
        prefs.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reconfigure() }
            .store(in: &cancellables)
        reconfigure()
    }

    func reconfigure() {
        sampleTimer?.invalidate(); sampleTimer = nil
        scheduleTimer?.invalidate(); scheduleTimer = nil
        lastBytes = nil; networkActive = false

        if prefs.triggersEnabled && (!prefs.processNames.isEmpty || prefs.triggerNetworkKBps > 0) {
            let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.sampleAndEvaluate() }
            }
            t.tolerance = 10
            RunLoop.main.add(t, forMode: .common)
            sampleTimer = t
            if prefs.triggerNetworkKBps > 0 { sampleNetwork() }
        }
        scheduleNextBoundary()
        evaluate()
    }

    private func scheduleNextBoundary() {
        guard prefs.triggersEnabled, prefs.scheduleEnabled,
              let next = prefs.scheduleWindow.nextBoundary(after: Date()) else { return }
        let t = Timer(fire: next.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.scheduleNextBoundary(); self?.evaluate() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        scheduleTimer = t
    }

    private func sampleAndEvaluate() {
        sampleNetwork()
        evaluate()
    }

    private func sampleNetwork() {
        guard prefs.triggerNetworkKBps > 0 else { networkActive = false; return }
        let now = Date(), bytes = NetworkCounter.totalBytes()
        defer { lastBytes = bytes; lastSampleDate = now }
        guard let prev = lastBytes, let prevDate = lastSampleDate, bytes >= prev else { return }
        let kbps = Double(bytes - prev) / 1024 / max(1, now.timeIntervalSince(prevDate))
        networkActive = kbps >= Double(prefs.triggerNetworkKBps)
    }

    func evaluate() {
        let reason = computeReason()
        if reason != currentReason {
            currentReason = reason
            onChange?(reason)
        }
    }

    private func computeReason() -> String? {
        guard prefs.triggersEnabled else { return nil }
        if !prefs.triggerApps.isEmpty {
            let wanted = Set(prefs.triggerApps)
            if let app = NSWorkspace.shared.runningApplications.first(where: { wanted.contains($0.bundleIdentifier ?? "") }) {
                return L("trigger.reason.app", app.localizedName ?? app.bundleIdentifier ?? "?")
            }
        }
        let names = prefs.processNames
        if !names.isEmpty, sampleTimer != nil {
            let running = ProcessList.names()
            if let hit = names.first(where: running.contains) {
                return L("trigger.reason.process", hit)
            }
        }
        if networkActive { return L("trigger.reason.network") }
        if prefs.triggerOnAC {
            let b = BatteryInfo.current()
            if !b.hasBattery || !b.onBattery { return L("trigger.reason.ac") }
        }
        if prefs.triggerExternalDisplay, Displays.hasExternal { return L("trigger.reason.display") }
        if prefs.scheduleEnabled, prefs.scheduleWindow.contains(Date()) { return L("trigger.reason.schedule") }
        return nil
    }
}

// MARK: - Update checker (GitHub Releases, once a day)

struct UpdateInfo: Equatable {
    var version: String
    var url: URL
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let releasesAPI = URL(string: "https://api.github.com/repos/dikeckaan/AwakeMAC/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/dikeckaan/AwakeMAC/releases/latest")!

    @Published private(set) var available: UpdateInfo?
    @Published private(set) var lastCheck: Date?
    @Published private(set) var checking = false
    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(force: false) }
        }
        t.tolerance = 3600
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Task { try? await Task.sleep(nanoseconds: 8_000_000_000); await check(force: false) }
    }

    func check(force: Bool) async {
        guard force || Prefs.shared.checkUpdates, !checking else { return }
        checking = true
        defer { checking = false; lastCheck = Date() }
        var req = URLRequest(url: Self.releasesAPI)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("AwakeMac-UpdateCheck", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else { return }
        let url = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? Self.releasesPage
        available = Version.isNewer(tag, than: currentVersion) ? UpdateInfo(version: tag, url: url) : nil
    }
}
