import Foundation

/// Looks up a string in the app bundle's `<lang>.lproj/Localizable.strings`.
/// Translations are generated from `scripts/translations.py`.
func L(_ key: String, _ args: CVarArg...) -> String {
    let s = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    return args.isEmpty ? s : String(format: s, locale: Locale.current, arguments: args)
}

/// Locale-aware percentage: "76%" in English, "%76" in Turkish, "76 %" in French …
func pct(_ n: Int) -> String {
    (Double(n) / 100).formatted(.percent.precision(.fractionLength(0)))
}

/// "30 min", "1 hr", "30 Min.", "30 分钟" … straight from the system formatter.
func shortDuration(_ seconds: Int) -> String {
    let f = DateComponentsFormatter()
    f.unitsStyle = .short
    f.allowedUnits = seconds >= 3600 ? [.hour] : [.minute]
    return f.string(from: TimeInterval(seconds)) ?? "\(seconds / 60)"
}
