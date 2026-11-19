import AppKit
import Foundation

/// Talks to `pmset` through a narrowly scoped sudoers rule.
///
/// The rule is installed once (the user authenticates in macOS' own admin
/// dialog — Awake Mac never sees or stores the password) and only allows these
/// two exact commands without a password:
///
///     /usr/bin/pmset -a disablesleep 1
///     /usr/bin/pmset -a disablesleep 0
enum SleepControl {
    static let pmset = "/usr/bin/pmset"
    static let sudo = "/usr/bin/sudo"
    static let rulePath = "/etc/sudoers.d/awakemac"
    /// Rule file name used by pre-release builds (app was called LidAwake).
    static let legacyRulePath = "/etc/sudoers.d/lidawake"

    enum SetupError: LocalizedError {
        case cancelled
        case invalidUser
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: return L("error.cancelled")
            case .invalidUser: return L("error.invalidUser")
            case .failed(let msg): return L("error.failed", msg)
            }
        }
    }

    // MARK: - Process helpers

    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: - State

    /// True if the sudoers rule exists and sudo accepts our command without a password.
    static func isAuthorized() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rulePath) || fm.fileExists(atPath: legacyRulePath) else { return false }
        return run(sudo, ["-n", "-l", pmset, "-a", "disablesleep", "1"]).status == 0
    }

    /// Reads `pmset -g` and reports whether `SleepDisabled` is currently 1.
    static func isSleepDisabled() -> Bool {
        let out = run(pmset, ["-g"]).output
        for line in out.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == "SleepDisabled" {
                return parts[1] == "1"
            }
        }
        return false
    }

    /// Runs `sudo -n pmset -a disablesleep 0|1`. Never prompts.
    @discardableResult
    static func setSleepDisabled(_ disabled: Bool) -> Bool {
        run(sudo, ["-n", pmset, "-a", "disablesleep", disabled ? "1" : "0"]).status == 0
    }

    // MARK: - One-time setup

    static func install() throws {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            throw SetupError.invalidUser
        }
        let lines = [
            "# Installed by Awake Mac. Allows ONLY these two commands without a password.",
            "# Remove with: sudo rm \(rulePath)",
            "\(user) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 1, \(pmset) -a disablesleep 0",
        ]
        let quoted = lines.map { "'\($0)'" }.joined(separator: " ")
        let tmp = "/etc/sudoers.d/.awakemac.new" // dotfiles are ignored by sudo's includedir
        let script = [
            "umask 0337",
            "/usr/bin/printf '%s\\n' \(quoted) > \(tmp)",
            "/usr/sbin/chown root:wheel \(tmp)",
            "/bin/chmod 0440 \(tmp)",
            "/usr/sbin/visudo -cf \(tmp) >/dev/null",
            "/bin/mv -f \(tmp) \(rulePath)",
            "/bin/rm -f \(legacyRulePath)",
        ].joined(separator: " && ") + " || { /bin/rm -f \(tmp); exit 1; }"

        try runAsAdmin(script, prompt: L("prompt.install"))
    }

    static func uninstall() throws {
        setSleepDisabled(false)
        try runAsAdmin("/usr/bin/pmset -a disablesleep 0; /bin/rm -f \(rulePath) \(legacyRulePath)",
                       prompt: L("prompt.remove"))
    }

    private static func runAsAdmin(_ shell: String, prompt: String) throws {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let source = "do shell script \"\(esc(shell))\" with prompt \"\(esc(prompt))\" with administrator privileges"
        var err: NSDictionary?
        guard let apple = NSAppleScript(source: source) else { throw SetupError.failed("AppleScript") }
        apple.executeAndReturnError(&err)
        if let err {
            if (err[NSAppleScript.errorNumber] as? Int) == -128 { throw SetupError.cancelled }
            throw SetupError.failed(err[NSAppleScript.errorMessage] as? String ?? "unknown error")
        }
    }
}
