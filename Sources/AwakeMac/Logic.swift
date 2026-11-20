import Foundation

/// A daily time window in minutes after midnight. `start > end` wraps past midnight
/// (e.g. 23:00–07:00). `start == end` means an empty window.
struct DailyWindow: Equatable {
    var start: Int
    var end: Int

    static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    func contains(minute m: Int) -> Bool {
        if start == end { return false }
        if start < end { return m >= start && m < end }
        return m >= start || m < end
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        contains(minute: Self.minutes(of: date, calendar: calendar))
    }

    /// The next moment (strictly after `date`) at which the window opens or closes.
    func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date? {
        guard start != end else { return nil }
        let candidates = [start, end].compactMap { minute -> Date? in
            calendar.nextDate(after: date,
                              matching: DateComponents(hour: minute / 60, minute: minute % 60, second: 0),
                              matchingPolicy: .nextTime)
        }
        return candidates.min()
    }
}

enum Version {
    /// True if `a` is a newer dotted version than `b` ("1.10.0" > "1.9.3"). A leading "v" is ignored.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

enum URLCommand: Equatable {
    case off, toggle
    case mode(AwakeMode, minutes: Int?)

    /// awakemac://off · awakemac://toggle · awakemac://light?minutes=30 · awakemac://lid?minutes=60
    init?(url: URL) {
        guard url.scheme?.lowercased() == "awakemac", let host = url.host?.lowercased() else { return nil }
        let minutes = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "minutes" })?.value.flatMap(Int.init)
            .flatMap { $0 > 0 ? $0 : nil }
        switch host {
        case "off": self = .off
        case "toggle": self = .toggle
        case "light": self = .mode(.light, minutes: minutes)
        case "lid": self = .mode(.lid, minutes: minutes)
        default: return nil
        }
    }
}

/// "1:24" for the menu bar.
func compactRemaining(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded(.up)))
    return String(format: "%d:%02d", minutes / 60, minutes % 60)
}
