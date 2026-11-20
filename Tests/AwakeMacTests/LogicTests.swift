@testable import AwakeMac
import XCTest

final class DailyWindowTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }

    private func date(_ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: h, minute: m))!
    }

    func testSameDayWindow() {
        let w = DailyWindow(start: 60, end: 420) // 01:00–07:00
        XCTAssertFalse(w.contains(date(0, 59), calendar: cal))
        XCTAssertTrue(w.contains(date(1, 0), calendar: cal))
        XCTAssertTrue(w.contains(date(6, 59), calendar: cal))
        XCTAssertFalse(w.contains(date(7, 0), calendar: cal))
    }

    func testOvernightWindow() {
        let w = DailyWindow(start: 23 * 60, end: 7 * 60) // 23:00–07:00
        XCTAssertTrue(w.contains(date(23, 30), calendar: cal))
        XCTAssertTrue(w.contains(date(3, 0), calendar: cal))
        XCTAssertFalse(w.contains(date(12, 0), calendar: cal))
    }

    func testEmptyWindow() {
        let w = DailyWindow(start: 300, end: 300)
        XCTAssertFalse(w.contains(minute: 300))
        XCTAssertNil(w.nextBoundary(after: date(1, 0), calendar: cal))
    }

    func testNextBoundary() {
        let w = DailyWindow(start: 60, end: 420)
        XCTAssertEqual(w.nextBoundary(after: date(0, 30), calendar: cal), date(1, 0))
        XCTAssertEqual(w.nextBoundary(after: date(2, 0), calendar: cal), date(7, 0))
        let tomorrow = cal.date(byAdding: .day, value: 1, to: date(1, 0))!
        XCTAssertEqual(w.nextBoundary(after: date(8, 0), calendar: cal), tomorrow)
    }
}

final class VersionTests: XCTestCase {
    func testComparison() {
        XCTAssertTrue(Version.isNewer("v1.2.0", than: "1.1.1"))
        XCTAssertTrue(Version.isNewer("1.10.0", than: "1.9.9"))
        XCTAssertTrue(Version.isNewer("2", than: "1.99"))
        XCTAssertFalse(Version.isNewer("1.1.1", than: "1.1.1"))
        XCTAssertFalse(Version.isNewer("v1.1.0", than: "1.1.1"))
        XCTAssertFalse(Version.isNewer("1.1", than: "1.1.0"))
    }
}

final class URLCommandTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(URLCommand(url: URL(string: "awakemac://off")!), .off)
        XCTAssertEqual(URLCommand(url: URL(string: "awakemac://toggle")!), .toggle)
        XCTAssertEqual(URLCommand(url: URL(string: "awakemac://lid?minutes=60")!), .mode(.lid, minutes: 60))
        XCTAssertEqual(URLCommand(url: URL(string: "AWAKEMAC://Light")!), .mode(.light, minutes: nil))
        XCTAssertEqual(URLCommand(url: URL(string: "awakemac://light?minutes=-5")!), .mode(.light, minutes: nil))
        XCTAssertNil(URLCommand(url: URL(string: "awakemac://reboot")!))
        XCTAssertNil(URLCommand(url: URL(string: "https://lid")!))
    }

    func testCompactRemaining() {
        XCTAssertEqual(compactRemaining(5400), "1:30")
        XCTAssertEqual(compactRemaining(61), "0:02")
        XCTAssertEqual(compactRemaining(-5), "0:00")
    }
}

final class LocalizationTests: XCTestCase {
    private func table(_ lang: String) throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/\(lang).lproj/Localizable.strings")
        let dict = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "unreadable \(lang)")
        return dict
    }

    private func specifiers(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: "%(\\d\\$)?@")
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { _ in "@" }
    }

    func testAllLanguagesCompleteAndFormatSafe() throws {
        let en = try table("en")
        let langs = ["tr", "de", "fr", "es", "it", "pt-BR", "nl", "pl", "ru", "uk", "ja", "ko", "zh-Hans", "ar"]
        for lang in langs {
            let t = try table(lang)
            XCTAssertEqual(Set(t.keys), Set(en.keys), "\(lang) keys differ")
            for (k, v) in en {
                XCTAssertEqual(specifiers(t[k] ?? "").count, specifiers(v).count, "\(lang): \(k) format mismatch")
            }
        }
    }

    func testCodeUsesOnlyKnownKeys() throws {
        let en = try table("en")
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AwakeMac")
        let re = try NSRegularExpression(pattern: "L\\(\"([A-Za-z0-9._]+)\"")
        for file in try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(m.range(at: 1), in: text)!])
                XCTAssertNotNil(en[key], "\(file.lastPathComponent): missing key \(key)")
            }
        }
    }
}
