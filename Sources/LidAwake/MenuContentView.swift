import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var c: AwakeController
    @StateObject private var ui = ToggleState()
    var forceSettingsOpen = false

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
                SectionLabel(text: "Süre")
                Picker("Süre", selection: $c.duration) {
                    ForEach(AwakeDuration.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            StatusStrip()

            if let n = c.notice {
                NoticeBanner(notice: n) { c.notice = nil }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().opacity(0.6)

            SettingsSection(expanded: forceSettingsOpen ? .constant(true) : $ui.value)

            FooterBar()
        }
        .padding(16)
        .frame(width: 340)
        .animation(.easeOut(duration: 0.18), value: c.notice)
        .animation(.easeOut(duration: 0.18), value: ui.value)
        .onAppear { if !forceSettingsOpen { c.refreshSystemState() } }
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
                    Text("LidAwake")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    if c.sleepDisabledInSystem {
                        Text("SleepDisabled 1")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AwakeMode.lid.colors[0].opacity(0.16)))
                            .foregroundStyle(AwakeMode.lid.colors[0])
                            .help("pmset -g çıktısında SleepDisabled = 1")
                    }
                }
                statusLine
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var statusLine: Text {
        let prefix: String
        switch c.mode {
        case .off: return Text("Mac normal şekilde uyur")
        case .light: prefix = "Sistem uyumaz"
        case .lid: prefix = "Kapak kapalıyken de uyanık"
        }
        if let end = c.endDate {
            return Text("\(prefix) · ") + Text(end, style: .timer).monospacedDigit()
        }
        return Text("\(prefix) · süresiz")
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

private struct SetupCard: View {
    @EnvironmentObject private var c: AwakeController

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18))
                .foregroundStyle(AwakeMode.lid.colors[0])
            VStack(alignment: .leading, spacing: 6) {
                Text("Tek seferlik kurulum")
                    .font(.system(size: 12, weight: .semibold))
                Text("Kapak kapalı modu için yalnızca `pmset -a disablesleep 0/1` komutlarına izin veren dar bir sudoers kuralı eklenir. Şifren macOS'in kendi penceresinde sorulur, uygulama saklamaz.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Kur…") { c.installHelper() }
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

    var body: some View {
        HStack(spacing: 8) {
            Chip(symbol: c.battery.symbol, title: c.battery.label, subtitle: c.battery.sourceLabel,
                 tint: batteryTint)
            Chip(symbol: c.thermalState.symbol, title: c.thermalState.label, subtitle: "Isı",
                 tint: thermalTint)
            Chip(symbol: "shield.lefthalf.filled", title: c.batteryThreshold == 0 ? "Kapalı" : "%\(c.batteryThreshold)",
                 subtitle: "Pil eşiği", tint: .secondary)
        }
    }

    private var batteryTint: Color {
        guard c.battery.hasBattery, c.battery.onBattery else { return .green }
        if c.batteryThreshold > 0 && c.battery.level <= c.batteryThreshold + 5 { return .orange }
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
                Text(subtitle).font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
    }
}

// MARK: - Notice

private struct NoticeBanner: View {
    let notice: Notice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: notice.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isWarning ? Color.orange : Color.green)
            Text(notice.text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill((notice.isWarning ? Color.orange : Color.green).opacity(0.12)))
    }
}

// MARK: - Settings

private struct SettingsSection: View {
    @EnvironmentObject private var c: AwakeController
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                expanded.toggle()
            } label: {
                HStack {
                    SectionLabel(text: "Ayarlar")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    SettingRow(symbol: "power", title: "Girişte başlat") {
                        Toggle("", isOn: Binding(get: { c.launchAtLogin }, set: { c.setLaunchAtLogin($0) }))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                    if let note = c.loginItemNote {
                        Text(note).font(.system(size: 10.5)).foregroundStyle(.orange)
                    }

                    SettingRow(symbol: "battery.25", title: "Pil eşiğinde kapat") {
                        Picker("", selection: $c.batteryThreshold) {
                            ForEach(AwakeController.thresholdChoices, id: \.self) { v in
                                Text(v == 0 ? "Kapalı" : "%\(v)").tag(v)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }

                    SettingRow(symbol: "lock.shield", title: "Yetki (sudoers)") {
                        if c.helperInstalled {
                            HStack(spacing: 8) {
                                Label("Kurulu", systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.green)
                                Button("Kaldır") { c.uninstallHelper() }
                                    .controlSize(.small)
                            }
                        } else {
                            Button("Kur…") { c.installHelper() }
                                .controlSize(.small)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

private struct SettingRow<Trailing: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title).font(.system(size: 12))
            Spacer()
            trailing
        }
        .frame(minHeight: 22)
    }
}

private struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased(with: Locale(identifier: "tr_TR")))
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

private struct FooterBar: View {
    var body: some View {
        HStack {
            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Çıkış", systemImage: "power")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
            .help("Çıkarken uyku ayarı her zaman geri alınır")
        }
    }
}

/// Small observable flag. (Used instead of `@State`, whose macro plugin ships only with
/// full Xcode — this keeps the project buildable with the Command Line Tools alone.)
final class ToggleState: ObservableObject {
    @Published var value = false
}
