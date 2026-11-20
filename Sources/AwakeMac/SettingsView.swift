import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label(L("tab.general"), systemImage: "gearshape") }
            SafetyTab().tabItem { Label(L("tab.safety"), systemImage: "shield.lefthalf.filled") }
            TriggersTab().tabItem { Label(L("tab.triggers"), systemImage: "wand.and.stars") }
            AboutTab().tabItem { Label(L("tab.about"), systemImage: "info.circle") }
        }
        .frame(width: 520)
        .padding(.top, 4)
    }
}

// MARK: - Building blocks

private struct Row<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 3)
    }
}

private struct SwitchRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Row(title: title, detail: detail) {
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }
}

private func minutesBinding(_ binding: Binding<Int>) -> Binding<Date> {
    Binding<Date>(
        get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(binding.wrappedValue * 60)) },
        set: { binding.wrappedValue = DailyWindow.minutes(of: $0) }
    )
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject private var c: AwakeController
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section {
                Row(title: L("settings.launchAtLogin"), detail: c.loginItemNote) {
                    Toggle("", isOn: Binding(get: { c.launchAtLogin }, set: { c.setLaunchAtLogin($0) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                SwitchRow(title: L("settings.remember"),
                          detail: L(prefs.rememberMode ? "settings.remember.on" : "settings.remember.off"),
                          isOn: $prefs.rememberMode)
            }
            Section {
                SwitchRow(title: L("settings.menuBarTime"), detail: L("settings.menuBarTime.detail"),
                          isOn: $prefs.showTimeInMenuBar)
                SwitchRow(title: L("settings.hotkey"), detail: L("hotkey.help"), isOn: $prefs.hotkeyEnabled)
                SwitchRow(title: L("settings.keepDisplayOn"), detail: L("settings.keepDisplayOn.detail"),
                          isOn: $prefs.keepDisplayOn)
            }
            Section {
                Row(title: L("settings.language"), detail: L("settings.language.detail")) {
                    Button(L("settings.language.open")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 430)
    }
}

// MARK: - Safety

private struct SafetyTab: View {
    @EnvironmentObject private var c: AwakeController
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section {
                Row(title: L("settings.threshold"), detail: L("settings.threshold.detail")) {
                    Picker("", selection: $prefs.batteryThreshold) {
                        ForEach(Prefs.thresholdChoices, id: \.self) { v in
                            Text(v == 0 ? L("settings.off") : pct(v)).tag(v)
                        }
                    }
                    .labelsHidden().fixedSize()
                }
                SwitchRow(title: L("settings.lidOnlyOnAC"), detail: L("settings.lidOnlyOnAC.detail"), isOn: $prefs.lidOnlyOnAC)
                SwitchRow(title: L("settings.lockOnLidClose"), detail: L("settings.lockOnLidClose.detail"), isOn: $prefs.lockOnLidClose)
                SwitchRow(title: L("settings.heatWarning"), detail: L("settings.heatWarning.detail"), isOn: $prefs.heatWarning)
                SwitchRow(title: L("settings.expiryWarning"), detail: L("settings.expiryWarning.detail"), isOn: $prefs.expiryWarning)
            }
            Section {
                Row(title: L("settings.privilege"), detail: L("settings.privilege.detail")) {
                    if c.helperInstalled {
                        HStack(spacing: 8) {
                            Label(L("setup.installed"), systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green).fixedSize()
                            Button(L("setup.remove")) { c.uninstallHelper() }.controlSize(.small).fixedSize()
                        }
                    } else {
                        Button(L("setup.install")) { c.installHelper() }.controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 430)
    }
}

// MARK: - Triggers

private struct TriggersTab: View {
    @EnvironmentObject private var c: AwakeController
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section {
                SwitchRow(title: L("triggers.enabled"), detail: L("triggers.enabled.detail"), isOn: $prefs.triggersEnabled)
                Row(title: L("triggers.mode")) {
                    Picker("", selection: $prefs.triggerMode) {
                        Text(AwakeMode.light.title).tag(AwakeMode.light)
                        Text(AwakeMode.lid.title).tag(AwakeMode.lid)
                    }
                    .labelsHidden().fixedSize()
                }
            }
            Group {
                Section(L("triggers.apps")) {
                    ForEach(prefs.triggerApps, id: \.self) { id in
                        HStack {
                            AppLabel(bundleID: id)
                            Spacer()
                            Button {
                                prefs.triggerApps.removeAll { $0 == id }
                            } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    Button(L("triggers.apps.add")) { addApp() }.controlSize(.small)
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("triggers.processes"))
                        TextField("ffmpeg, rsync, xcodebuild", text: $prefs.triggerProcesses)
                            .textFieldStyle(.roundedBorder)
                        Text(L("triggers.processes.detail")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Row(title: L("triggers.network"), detail: L("triggers.network.detail")) {
                        Picker("", selection: $prefs.triggerNetworkKBps) {
                            ForEach(Prefs.networkChoices, id: \.self) { v in
                                Text(v == 0 ? L("settings.off") : "≥ \(ByteCountFormatter.string(fromByteCount: Int64(v) * 1024, countStyle: .binary))/s").tag(v)
                            }
                        }
                        .labelsHidden().fixedSize()
                    }
                    SwitchRow(title: L("triggers.ac"), isOn: $prefs.triggerOnAC)
                    SwitchRow(title: L("triggers.display"), isOn: $prefs.triggerExternalDisplay)
                }
                Section {
                    SwitchRow(title: L("triggers.schedule"), detail: L("triggers.schedule.detail"), isOn: $prefs.scheduleEnabled)
                    if prefs.scheduleEnabled {
                        HStack {
                            DatePicker(L("triggers.schedule.from"), selection: minutesBinding($prefs.scheduleStart),
                                       displayedComponents: .hourAndMinute)
                            DatePicker(L("triggers.schedule.to"), selection: minutesBinding($prefs.scheduleEnd),
                                       displayedComponents: .hourAndMinute)
                        }
                    }
                }
            }
            .disabled(!prefs.triggersEnabled)
        }
        .formStyle(.grouped)
        .frame(height: 430)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !prefs.triggerApps.contains(id) {
                prefs.triggerApps.append(id)
            }
        }
    }
}

private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().frame(width: 18, height: 18)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Awake Mac").font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(L("about.version", updates.currentVersion)).foregroundStyle(.secondary)
                        Link("github.com/dikeckaan/AwakeMAC", destination: URL(string: "https://github.com/dikeckaan/AwakeMAC")!)
                    }
                }
            }
            Section {
                SwitchRow(title: L("settings.checkUpdates"), isOn: $prefs.checkUpdates)
                Row(title: updateStatus) {
                    if let u = updates.available {
                        Button(L("update.download")) { NSWorkspace.shared.open(u.url) }.controlSize(.small)
                    } else {
                        Button(L("update.checkNow")) { Task { await updates.check(force: true) } }
                            .controlSize(.small).disabled(updates.checking)
                    }
                }
            }
            Section(L("about.automation")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("about.automation.detail")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("open awakemac://lid?minutes=60\nopen awakemac://light\nopen awakemac://toggle\nopen awakemac://off")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 430)
    }

    private var updateStatus: String {
        if let u = updates.available { return L("update.available", u.version) }
        if updates.checking { return L("update.checking") }
        return updates.lastCheck == nil ? L("update.notChecked") : L("update.upToDate")
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject private var c: AwakeController
    var done: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 88, height: 88)
            VStack(spacing: 4) {
                Text(L("onboarding.title")).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(L("onboarding.subtitle")).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 12) {
                Feature(mode: .light, text: L("mode.light.help"))
                Feature(mode: .lid, text: L("mode.lid.help"))
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 20)).foregroundStyle(.green).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("tab.safety")).fontWeight(.semibold)
                        Text(L("onboarding.safety")).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))

            if !c.helperInstalled {
                SetupCard()
            }
            HStack {
                Text(L("onboarding.menubar")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Button(L("onboarding.start")) { done() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private struct Feature: View {
        let mode: AwakeMode
        let text: String
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mode.symbol).font(.system(size: 20))
                    .foregroundStyle(LinearGradient(colors: mode.colors, startPoint: .top, endPoint: .bottom))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title).fontWeight(.semibold)
                    Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Windows

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func showSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(AwakeController.shared))
            let w = NSWindow(contentViewController: host)
            w.title = L("settings.window")
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        AwakeController.shared.refreshSystemState()
        present(settingsWindow)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView { [weak self] in
                Prefs.shared.onboardingDone = true
                self?.onboardingWindow?.close()
            }
            let host = NSHostingController(rootView: view.environmentObject(AwakeController.shared))
            let w = NSWindow(contentViewController: host)
            w.title = "Awake Mac"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            onboardingWindow = w
        }
        present(onboardingWindow)
    }

    private func present(_ w: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        w?.makeKeyAndOrderFront(nil)
    }
}
