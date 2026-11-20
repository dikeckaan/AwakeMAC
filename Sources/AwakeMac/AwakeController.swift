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
        case .off: return L("mode.off")
        case .light: return L("mode.light")
        case .lid: return L("mode.lid")
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
        case .off: return L("mode.off.help")
        case .light: return L("mode.light.help")
        case .lid: return L("mode.lid.help")
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
        case .forever: return L("duration.forever")
        default: return shortDuration(rawValue)
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
        static let lidActive = "lidModeActive" // crash-recovery marker
        static let loginConfigured = "loginItemConfigured"
        static let savedMode = "savedMode"
        static let savedEnd = "savedEnd" // seconds since 1970, 0 = no time limit
    }

    nonisolated static let expiryCategory = "AWAKE_EXPIRY"
    nonisolated static let extendAction = "EXTEND_30"

    let prefs = Prefs.shared

    @Published private(set) var mode: AwakeMode = .off
    @Published private(set) var endDate: Date?
    /// Non-nil while the current mode was switched on by an automatic trigger.
    @Published private(set) var autoReason: String?
    @Published private(set) var helperInstalled = false
    @Published private(set) var sleepDisabledInSystem = false
    @Published private(set) var battery = BatteryInfo.current()
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginItemNote: String?
    @Published var notice: Notice?

    private var idleAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private var hasIdleAssertion = false
    private var hasDisplayAssertion = false
    private var expiryTimer: Timer?
    private var bootstrapped = false
    private var autoSuppressed = false // user turned an auto session off; wait for conditions to clear
    private var heatWarned = false
    private var cancellables: Set<AnyCancellable> = []
    private let defaults = UserDefaults.standard
    private let powerObserver = PowerSourceObserver()
    private let clamshell = ClamshellMonitor()
    let triggers = TriggerMonitor()

    // MARK: - Lifecycle

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true

        // A previous run crashed or was force-killed while lid mode was on: undo it.
        if defaults.bool(forKey: Keys.lidActive) {
            if SleepControl.setSleepDisabled(false) {
                notice = Notice(text: L("notice.recovered"), isWarning: false)
            }
            defaults.set(false, forKey: Keys.lidActive)
        }

        if !defaults.bool(forKey: Keys.loginConfigured) {
            try? LoginItem.set(true) // default: launch at login ON
            defaults.set(true, forKey: Keys.loginConfigured)
        }

        refreshSystemState()
        setUpNotifications()

        // Everything below is event driven — no polling while idle.
        powerObserver.start { [weak self] in
            Task { @MainActor in self?.powerChanged() }
        }
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkSafety() }
        }
        clamshell.start { [weak self] closed in
            Task { @MainActor in self?.lidChanged(closed: closed) }
        }
        prefs.$keepDisplayOn.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyAssertions() }
        }.store(in: &cancellables)
        prefs.$rememberMode.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.persistSelection() }
        }.store(in: &cancellables)
        prefs.$batteryThreshold.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.checkSafety() }
        }.store(in: &cancellables)
        prefs.$lidOnlyOnAC.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.checkSafety() }
        }.store(in: &cancellables)
        prefs.$duration.dropFirst().sink { [weak self] d in
            DispatchQueue.main.async {
                guard let self, self.mode != .off, self.autoReason == nil else { return }
                self.scheduleExpiry(until: d == .forever ? nil : Date().addingTimeInterval(TimeInterval(d.rawValue)))
            }
        }.store(in: &cancellables)

        restoreRememberedMode()
        triggers.start { [weak self] reason in self?.triggerChanged(reason) }
        UpdateChecker.shared.start()
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
        if d.bool(forKey: Keys.lidActive), SleepControl.setSleepDisabled(false) {
            d.set(false, forKey: Keys.lidActive)
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["expiry"])
        // IOPM assertions are released automatically when the process exits.
    }

    // MARK: - Public actions

    /// Manual selection from the UI, menu, hot key, URL or Shortcuts.
    func select(_ newMode: AwakeMode, minutes: Int? = nil) {
        notice = nil
        if newMode == .off {
            if autoReason != nil { autoSuppressed = true }
            deactivate(reason: nil)
            return
        }
        let end: Date?
        if let minutes { end = Date().addingTimeInterval(TimeInterval(minutes * 60)) }
        else if prefs.duration == .forever { end = nil }
        else { end = Date().addingTimeInterval(TimeInterval(prefs.duration.rawValue)) }

        if activate(newMode, until: end) {
            autoReason = nil
            prefs.lastMode = newMode
            persistSelection()
        }
    }

    func toggle() {
        if mode == .off {
            let preferred = prefs.lastMode == .off ? AwakeMode.light : prefs.lastMode
            select(preferred == .lid && !helperInstalled ? .light : preferred)
        } else {
            select(.off)
        }
    }

    /// Custom end time for the current (or last used) mode.
    func keepAwake(until end: Date) {
        guard end > Date() else { return }
        if mode == .off {
            let m = prefs.lastMode == .off ? AwakeMode.light : prefs.lastMode
            if activate(m == .lid && !helperInstalled ? .light : m, until: end) { autoReason = nil }
        } else {
            autoReason = nil
            scheduleExpiry(until: end)
        }
        persistSelection()
    }

    func extend(by seconds: TimeInterval) {
        guard mode != .off else { return }
        let base = max(endDate ?? Date(), Date())
        scheduleExpiry(until: base.addingTimeInterval(seconds))
    }

    func handle(_ command: URLCommand) {
        switch command {
        case .off: select(.off)
        case .toggle: toggle()
        case .mode(let m, let minutes): select(m, minutes: minutes)
        }
    }

    // MARK: - Activation core

    @discardableResult
    private func activate(_ newMode: AwakeMode, until end: Date?) -> Bool {
        if newMode == .lid && !helperInstalled {
            refreshSystemState()
            if !helperInstalled {
                notice = Notice(text: L("notice.setupFirst"), isWarning: true)
                return false
            }
        }
        if let reason = safetyBlockReason(for: newMode) {
            notice = Notice(text: reason, isWarning: true)
            return false
        }

        if mode == .lid && newMode != .lid { setLid(false) }
        if newMode == .lid && mode != .lid {
            guard setLid(true) else {
                refreshSystemState()
                notice = Notice(text: L("notice.pmsetFailed"), isWarning: true)
                return false
            }
        }
        mode = newMode
        heatWarned = false
        applyAssertions()
        scheduleExpiry(until: end)
        sleepDisabledInSystem = SleepControl.isSleepDisabled()
        return true
    }

    private func deactivate(reason: String?) {
        expiryTimer?.invalidate()
        expiryTimer = nil
        endDate = nil
        cancelExpiryWarning()
        if mode == .lid || defaults.bool(forKey: Keys.lidActive) { setLid(false) }
        mode = .off
        autoReason = nil
        applyAssertions()
        persistSelection()
        sleepDisabledInSystem = SleepControl.isSleepDisabled()
        if let reason {
            notice = Notice(text: reason, isWarning: true)
            postNotification(reason)
        }
    }

    @discardableResult
    private func setLid(_ on: Bool) -> Bool {
        if on {
            defaults.set(true, forKey: Keys.lidActive) // before the command: a crash mid-way still recovers
            guard SleepControl.setSleepDisabled(true) else {
                defaults.set(false, forKey: Keys.lidActive)
                return false
            }
            return true
        }
        if SleepControl.setSleepDisabled(false) {
            defaults.set(false, forKey: Keys.lidActive)
            return true
        }
        notice = Notice(text: L("notice.restoreFailed"), isWarning: true)
        return false
    }

    private func scheduleExpiry(until end: Date?) {
        expiryTimer?.invalidate()
        expiryTimer = nil
        endDate = end
        cancelExpiryWarning()
        defer { persistSelection() }
        guard mode != .off, let end else { return }
        let timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.deactivate(reason: nil) }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
        scheduleExpiryWarning(end)
    }

    private func applyAssertions() {
        let active = mode != .off
        setAssertion(&idleAssertion, &hasIdleAssertion, on: active,
                     type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString)
        setAssertion(&displayAssertion, &hasDisplayAssertion, on: active && prefs.keepDisplayOn,
                     type: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString)
    }

    private func setAssertion(_ id: inout IOPMAssertionID, _ has: inout Bool, on: Bool, type: CFString) {
        if on && !has {
            has = IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                              "Awake Mac: user chose to stay awake" as CFString, &id) == kIOReturnSuccess
        } else if !on && has {
            IOPMAssertionRelease(id)
            has = false
        }
    }

    // MARK: - Triggers

    private func triggerChanged(_ reason: String?) {
        guard let reason else {
            autoSuppressed = false
            if autoReason != nil { deactivate(reason: nil) }
            return
        }
        if autoReason != nil {
            autoReason = reason // still automatic, maybe a different cause
            return
        }
        guard mode == .off, !autoSuppressed else { return }
        let m = prefs.triggerMode == .lid && !helperInstalled ? AwakeMode.light : prefs.triggerMode
        if activate(m, until: nil) { autoReason = reason }
    }

    // MARK: - Remember selection

    private func persistSelection() {
        guard prefs.rememberMode else {
            defaults.removeObject(forKey: Keys.savedMode)
            defaults.removeObject(forKey: Keys.savedEnd)
            return
        }
        guard autoReason == nil else { return } // automatic sessions are not "selections"
        defaults.set(mode.rawValue, forKey: Keys.savedMode)
        defaults.set(endDate?.timeIntervalSince1970 ?? 0, forKey: Keys.savedEnd)
    }

    /// Re-applies the last manual selection after launch when "Remember selection" is on.
    /// Expired timers are not restored; safety checks still apply.
    private func restoreRememberedMode() {
        guard prefs.rememberMode,
              let saved = defaults.string(forKey: Keys.savedMode).flatMap(AwakeMode.init(rawValue:)),
              saved != .off
        else { return }
        let endTS = defaults.double(forKey: Keys.savedEnd)
        if endTS > 0 && endTS <= Date().timeIntervalSince1970 {
            persistSelection()
            return
        }
        activate(saved, until: endTS > 0 ? Date(timeIntervalSince1970: endTS) : nil)
    }

    // MARK: - Safety

    private func safetyBlockReason(for m: AwakeMode) -> String? {
        let t = prefs.batteryThreshold
        if t > 0, battery.hasBattery, battery.onBattery, battery.level <= t {
            return L("notice.lowBattery", pct(battery.level), pct(t))
        }
        if m == .lid, prefs.lidOnlyOnAC, battery.hasBattery, battery.onBattery {
            return L("notice.lidNeedsAC")
        }
        if m == .lid, thermalState == .critical {
            return L("notice.tooHot")
        }
        return nil
    }

    private func powerChanged() {
        checkSafety()
        triggers.evaluate()
    }

    func checkSafety() {
        battery = .current()
        thermalState = ProcessInfo.processInfo.thermalState
        if mode == .lid { sleepDisabledInSystem = SleepControl.isSleepDisabled() }
        guard mode != .off else { return }
        if let reason = safetyBlockReason(for: mode) {
            if autoReason != nil { autoSuppressed = true }
            deactivate(reason: reason)
            return
        }
        if prefs.heatWarning, thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            if !heatWarned {
                heatWarned = true
                postNotification(L("notice.hot"))
            }
        } else if thermalState.rawValue <= ProcessInfo.ThermalState.fair.rawValue {
            heatWarned = false
        }
    }

    private func lidChanged(closed: Bool) {
        guard closed, mode == .lid, prefs.lockOnLidClose else { return }
        ScreenLock.lock()
    }

    // MARK: - Setup / settings

    func installHelper() {
        do {
            try SleepControl.install()
            refreshSystemState()
            notice = helperInstalled
                ? Notice(text: L("notice.setupDone"), isWarning: false)
                : Notice(text: L("notice.setupRejected"), isWarning: true)
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
            notice = Notice(text: L("notice.removed"), isWarning: false)
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
            notice = Notice(text: L("notice.loginFailed", error.localizedDescription), isWarning: true)
        }
        launchAtLogin = LoginItem.isEnabled
        loginItemNote = LoginItem.note
    }

    // MARK: - Notifications

    private func setUpNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationHandler.shared
        let extend = UNNotificationAction(identifier: Self.extendAction, title: L("notify.extend30"), options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.expiryCategory, actions: [extend], intentIdentifiers: [], options: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleExpiryWarning(_ end: Date) {
        let lead = end.timeIntervalSinceNow - 300
        guard prefs.expiryWarning, lead > 60 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Awake Mac"
        content.body = L("notify.expiring")
        content.categoryIdentifier = Self.expiryCategory
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: lead, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "expiry", content: content, trigger: trigger))
    }

    private func cancelExpiryWarning() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["expiry"])
    }

    private func postNotification(_ text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Awake Mac"
        content.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - Preview (used by --snapshot only)

    func applyPreview(mode: AwakeMode, remaining: TimeInterval, battery: BatteryInfo) {
        self.mode = mode
        self.endDate = Date().addingTimeInterval(remaining)
        self.battery = battery
        self.helperInstalled = true
        self.sleepDisabledInSystem = mode == .lid
        self.launchAtLogin = true
        self.thermalState = .nominal
    }
}

final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == AwakeController.extendAction {
            DispatchQueue.main.async { AwakeController.shared.extend(by: 1800) }
        }
        completionHandler()
    }
}
