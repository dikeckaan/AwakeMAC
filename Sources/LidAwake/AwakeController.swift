import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt
import SwiftUI
@preconcurrency import UserNotifications

enum AwakeMode: String, CaseIterable, Identifiable {
    case off, light, lid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Kapalı"
        case .light: return "Hafif"
        case .lid: return "Kapak kapalı"
        }
    }

    var symbol: String {
        switch self {
        case .off: return "moon.zzz.fill"
        case .light: return "cup.and.saucer.fill"
        case .lid: return "sun.max.fill"
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .off: return "moon.zzz"
        case .light: return "cup.and.saucer.fill"
        case .lid: return "sun.max.fill"
        }
    }

    var help: String {
        switch self {
        case .off: return "Mac normal enerji ayarlarına göre uyur."
        case .light: return "Boşta uykuyu engeller, ekran kapanabilir. Kapak kapanırsa Mac uyur."
        case .lid: return "Kapak kapalıyken bile uyumaz (pmset disablesleep 1). Ekran kapanabilir."
        }
    }

    var colors: [Color] {
        switch self {
        case .off: return [Color(red: 0.50, green: 0.53, blue: 0.60), Color(red: 0.33, green: 0.35, blue: 0.42)]
        case .light: return [Color(red: 1.00, green: 0.62, blue: 0.20), Color(red: 0.96, green: 0.36, blue: 0.40)]
        case .lid: return [Color(red: 0.40, green: 0.38, blue: 1.00), Color(red: 0.70, green: 0.30, blue: 0.95)]
        }
    }
}

enum AwakeDuration: Int, CaseIterable, Identifiable {
    case m30 = 1800, h1 = 3600, h2 = 7200, forever = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .m30: return "30 dk"
        case .h1: return "1 sa"
        case .h2: return "2 sa"
        case .forever: return "Süresiz"
        }
    }
}

struct Notice: Equatable {
    var text: String
    var isWarning: Bool
}

@MainActor
final class AwakeController: ObservableObject {
    static let shared = AwakeController()

    private enum Keys {
        static let duration = "duration"
        static let threshold = "batteryThreshold"
        static let lidActive = "lidModeActive" // crash-recovery marker
        static let loginConfigured = "loginItemConfigured"
    }

    static let thresholdChoices = [0, 10, 15, 20, 30, 40]

    @Published private(set) var mode: AwakeMode = .off
    @Published private(set) var endDate: Date?
    @Published private(set) var helperInstalled = false
    @Published private(set) var sleepDisabledInSystem = false
    @Published private(set) var battery = BatteryInfo.current()
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginItemNote: String?
    @Published var notice: Notice?

    @Published var duration: AwakeDuration {
        didSet {
            UserDefaults.standard.set(duration.rawValue, forKey: Keys.duration)
            if mode != .off { scheduleExpiry() }
        }
    }

    @Published var batteryThreshold: Int {
        didSet {
            UserDefaults.standard.set(batteryThreshold, forKey: Keys.threshold)
            poll()
        }
    }

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var expiryTimer: Timer?
    private var pollTimer: Timer?
    private var bootstrapped = false
    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [Keys.duration: AwakeDuration.forever.rawValue, Keys.threshold: 20])
        duration = AwakeDuration(rawValue: defaults.integer(forKey: Keys.duration)) ?? .forever
        batteryThreshold = defaults.integer(forKey: Keys.threshold)
    }

    // MARK: - Lifecycle

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true

        // If a previous run crashed or was force-killed while lid mode was on,
        // undo it now so the Mac does not stay sleepless forever.
        if defaults.bool(forKey: Keys.lidActive) {
            if SleepControl.setSleepDisabled(false) {
                notice = Notice(text: "Önceki oturumdan kalan 'uyku kapalı' ayarı geri alındı.", isWarning: false)
            }
            defaults.set(false, forKey: Keys.lidActive)
        }

        if !defaults.bool(forKey: Keys.loginConfigured) {
            try? LoginItem.set(true) // default: launch at login ON
            defaults.set(true, forKey: Keys.loginConfigured)
        }

        refreshSystemState()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func refreshSystemState() {
        helperInstalled = SleepControl.isAuthorized()
        sleepDisabledInSystem = SleepControl.isSleepDisabled()
        battery = .current()
        thermalState = ProcessInfo.processInfo.thermalState
        launchAtLogin = LoginItem.isEnabled
        loginItemNote = LoginItem.note
    }

    /// Synchronous, actor-independent restore used on quit, logout and signals.
    nonisolated static func restoreSystemDefaults() {
        let d = UserDefaults.standard
        if d.bool(forKey: Keys.lidActive) {
            if SleepControl.setSleepDisabled(false) {
                d.set(false, forKey: Keys.lidActive)
            }
        }
        // IOPM assertions are released automatically when the process exits.
    }

    // MARK: - Mode switching

    func select(_ newMode: AwakeMode) {
        notice = nil
        guard newMode != mode else { return }

        if newMode == .off {
            deactivate(reason: nil)
            return
        }
        if newMode == .lid && !helperInstalled {
            refreshSystemState()
            if !helperInstalled {
                notice = Notice(text: "Kapak kapalı modu için önce tek seferlik kurulumu yap.", isWarning: true)
                return
            }
        }
        if let reason = safetyBlockReason(for: newMode) {
            notice = Notice(text: reason, isWarning: true)
            return
        }

        teardown()

        switch newMode {
        case .light:
            guard createAssertion() else {
                notice = Notice(text: "Uyku engellenemedi (IOPMAssertion).", isWarning: true)
                return
            }
        case .lid:
            defaults.set(true, forKey: Keys.lidActive) // set before, so a crash mid-way still recovers
            guard SleepControl.setSleepDisabled(true) else {
                defaults.set(false, forKey: Keys.lidActive)
                refreshSystemState()
                notice = Notice(text: "pmset çalıştırılamadı. Kurulumu yenilemeyi dene.", isWarning: true)
                return
            }
            _ = createAssertion() // also keep idle-sleep off; harmless and helps on AC
        case .off:
            break
        }

        mode = newMode
        scheduleExpiry()
        sleepDisabledInSystem = SleepControl.isSleepDisabled()
    }

    private func deactivate(reason: String?) {
        teardown()
        mode = .off
        sleepDisabledInSystem = SleepControl.isSleepDisabled()
        if let reason {
            notice = Notice(text: reason, isWarning: true)
            postNotification(reason)
        }
    }

    private func teardown() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        endDate = nil
        releaseAssertion()
        if mode == .lid || defaults.bool(forKey: Keys.lidActive) {
            if SleepControl.setSleepDisabled(false) {
                defaults.set(false, forKey: Keys.lidActive)
            } else {
                notice = Notice(text: "Ayar geri alınamadı! Terminal: sudo pmset -a disablesleep 0", isWarning: true)
            }
        }
    }

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard mode != .off, duration != .forever else {
            endDate = nil
            return
        }
        let end = Date().addingTimeInterval(TimeInterval(duration.rawValue))
        endDate = end
        let timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.deactivate(reason: nil) }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    // MARK: - Safety

    private func safetyBlockReason(for m: AwakeMode) -> String? {
        if batteryThreshold > 0, battery.hasBattery, battery.onBattery, battery.level <= batteryThreshold {
            return "Pil %\(battery.level) — %\(batteryThreshold) eşiğinin altında, uyanık kalma kapatıldı."
        }
        if m == .lid, thermalState == .critical {
            return "Mac çok ısındı — kapak kapalı modu güvenlik için kapatıldı."
        }
        return nil
    }

    func poll() {
        battery = .current()
        thermalState = ProcessInfo.processInfo.thermalState
        sleepDisabledInSystem = SleepControl.isSleepDisabled()
        if mode != .off, let reason = safetyBlockReason(for: mode) {
            deactivate(reason: reason)
        }
    }

    // MARK: - Setup / settings

    func installHelper() {
        do {
            try SleepControl.install()
            refreshSystemState()
            notice = helperInstalled
                ? Notice(text: "Kurulum tamam. Artık kapak kapalı modu tek tıkla açılır.", isWarning: false)
                : Notice(text: "Kural eklendi ama sudo onu kabul etmedi.", isWarning: true)
        } catch SleepControl.SetupError.cancelled {
            notice = nil
        } catch {
            notice = Notice(text: error.localizedDescription, isWarning: true)
        }
    }

    func uninstallHelper() {
        if mode == .lid { deactivate(reason: nil) }
        do {
            try SleepControl.uninstall()
            notice = Notice(text: "Sudoers kuralı kaldırıldı.", isWarning: false)
        } catch SleepControl.SetupError.cancelled {
        } catch {
            notice = Notice(text: error.localizedDescription, isWarning: true)
        }
        refreshSystemState()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
        } catch {
            notice = Notice(text: "Giriş öğesi ayarlanamadı: \(error.localizedDescription)", isWarning: true)
        }
        launchAtLogin = LoginItem.isEnabled
        loginItemNote = LoginItem.note
    }

    // MARK: - IOPM assertion

    private func createAssertion() -> Bool {
        guard !hasAssertion else { return true }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "LidAwake: kullanıcı uyanık kalmayı seçti" as CFString,
            &assertionID
        )
        hasAssertion = result == kIOReturnSuccess
        return hasAssertion
    }

    private func releaseAssertion() {
        guard hasAssertion else { return }
        IOPMAssertionRelease(assertionID)
        hasAssertion = false
    }

    // MARK: - Notifications

    private func postNotification(_ text: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "LidAwake"
            content.body = text
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    // MARK: - Preview (used by --snapshot only)

    func applyPreview(mode: AwakeMode, remaining: TimeInterval, battery: BatteryInfo) {
        self.duration = .h2
        self.mode = mode
        self.endDate = Date().addingTimeInterval(remaining)
        self.battery = battery
        self.helperInstalled = true
        self.sleepDisabledInSystem = mode == .lid
        self.launchAtLogin = true
        self.thermalState = .nominal
    }
}
