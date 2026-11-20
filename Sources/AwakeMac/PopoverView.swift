import AppKit
import SwiftUI

/// The panel shown under the menu bar icon.
struct MenuContentView: View {
    @EnvironmentObject private var c: AwakeController
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var updates = UpdateChecker.shared
    @StateObject private var untilPicker = ToggleState()
    @StateObject private var untilDate = DateState()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderView()

            HStack(spacing: 8) {
                ForEach(AwakeMode.allCases) { m in
                    ModeTile(mode: m, selected: c.mode == m) { c.select(m) }
                }
            }

            if !c.helperInstalled {
                SetupCard()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel(text: L("section.duration"))
                    Spacer()
                    Menu {
                        ForEach([15, 180, 240, 480], id: \.self) { m in
                            Button(shortDuration(m * 60)) { c.keepAwake(until: Date().addingTimeInterval(TimeInterval(m * 60))) }
                        }
                        Divider()
                        Button(L("duration.until")) {
                            untilDate.value = c.endDate ?? Date().addingTimeInterval(3600)
                            untilPicker.value = true
                        }
                        if c.mode != .off {
                            Divider()
                            Button(L("duration.extend30")) { c.extend(by: 1800) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L("duration.custom"))
                }
                Picker(L("section.duration"), selection: $prefs.duration) {
                    ForEach(AwakeDuration.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if untilPicker.value {
                    HStack(spacing: 8) {
                        Text(L("duration.untilLabel")).font(.system(size: 11.5))
                        DatePicker("", selection: $untilDate.value, in: Date()..., displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.stepperField)
                        Spacer()
                        Button(L("action.ok")) {
                            c.keepAwake(until: untilDate.value)
                            untilPicker.value = false
                        }
                        .controlSize(.small)
                        .keyboardShortcut(.defaultAction)
                        Button {
                            untilPicker.value = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            StatusStrip()

            if let reason = c.autoReason {
                Banner(symbol: "wand.and.stars", tint: AwakeMode.lid.colors[0],
                       text: L("auto.active", reason), dismiss: nil)
            }
            if let update = updates.available {
                Banner(symbol: "arrow.down.circle.fill", tint: .blue,
                       text: L("update.available", update.version), dismiss: nil)
                    .onTapGesture { NSWorkspace.shared.open(update.url) }
                    .help(update.url.absoluteString)
            }
            if let n = c.notice {
                Banner(symbol: n.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                       tint: n.isWarning ? .orange : .green, text: n.text) { c.notice = nil }
            }

            Divider().opacity(0.6)
            FooterBar()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(width: 340)
    }
}

// MARK: - Header

private struct HeaderView: View {
    @EnvironmentObject private var c: AwakeController

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: c.mode.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .shadow(color: c.mode.colors[0].opacity(0.45), radius: 8, y: 3)
                Image(systemName: c.mode.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Awake Mac")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    if c.sleepDisabledInSystem {
                        Text("SleepDisabled 1")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AwakeMode.lid.colors[0].opacity(0.16)))
                            .foregroundStyle(AwakeMode.lid.colors[0])
                            .help(L("badge.help"))
                    }
                }
                statusLine
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var statusLine: Text {
        let prefix: String
        switch c.mode {
        case .off: return Text(L("status.off"))
        case .light: prefix = L("status.light")
        case .lid: prefix = L("status.lid")
        }
        if let end = c.endDate {
            return Text("\(prefix) · ") + Text(end, style: .timer).monospacedDigit()
        }
        return Text("\(prefix) · \(L("status.indefinite"))")
    }
}

// MARK: - Mode tile

private struct ModeTile: View {
    let mode: AwakeMode
    let selected: Bool
    let action: () -> Void
    @StateObject private var hover = ToggleState()

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 22)
                Text(mode.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: mode.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.primary.opacity(hover.value ? 0.10 : 0.055)))
                    .shadow(color: selected ? mode.colors[0].opacity(0.35) : .clear, radius: 6, y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(selected ? 0 : 0.08))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover.value = $0 }
        .help(mode.help)
        .animation(.easeOut(duration: 0.15), value: selected)
        .animation(.easeOut(duration: 0.12), value: hover.value)
    }
}

// MARK: - Setup card

struct SetupCard: View {
    @EnvironmentObject private var c: AwakeController

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18))
                .foregroundStyle(AwakeMode.lid.colors[0])
            VStack(alignment: .leading, spacing: 6) {
                Text(L("setup.title"))
                    .font(.system(size: 12, weight: .semibold))
                Text(L("setup.body"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("setup.install")) { c.installHelper() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AwakeMode.lid.colors[0].opacity(0.09)))
    }
}

// MARK: - Status strip

private struct StatusStrip: View {
    @EnvironmentObject private var c: AwakeController
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        HStack(spacing: 8) {
            Chip(symbol: c.battery.symbol, title: c.battery.label, subtitle: c.battery.sourceLabel, tint: batteryTint)
            Chip(symbol: c.thermalState.symbol, title: c.thermalState.label, subtitle: L("chip.heat"), tint: thermalTint)
            Chip(symbol: "shield.lefthalf.filled",
                 title: prefs.batteryThreshold == 0 ? L("settings.off") : pct(prefs.batteryThreshold),
                 subtitle: L("chip.threshold"), tint: .secondary)
        }
    }

    private var batteryTint: Color {
        guard c.battery.hasBattery, c.battery.onBattery else { return .green }
        if prefs.batteryThreshold > 0 && c.battery.level <= prefs.batteryThreshold + 5 { return .orange }
        return .primary
    }

    private var thermalTint: Color {
        switch c.thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        default: return .red
        }
    }
}

private struct Chip: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(subtitle).font(.system(size: 9.5)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
    }
}

// MARK: - Banner

private struct Banner: View {
    let symbol: String
    let tint: Color
    let text: String
    let dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.12)))
    }
}

// MARK: - Footer

private struct FooterBar: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        HStack(spacing: 14) {
            Button {
                WindowManager.shared.showSettings()
            } label: {
                Label(L("settings.open"), systemImage: "gearshape")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut(",")

            Spacer()

            if prefs.hotkeyEnabled {
                Text("⌥⌘A")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .help(L("hotkey.help"))
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Label(L("quit"), systemImage: "power")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
            .help(L("quit.help"))
        }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased(with: Locale.current))
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// Small observable values. (Used instead of `@State`, whose macro plugin ships only with
/// full Xcode — this keeps the package buildable with the Command Line Tools alone.)
final class ToggleState: ObservableObject {
    @Published var value = false
}

final class DateState: ObservableObject {
    @Published var value = Date()
}
