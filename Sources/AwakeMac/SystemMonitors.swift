import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

// MARK: - Power source changes (event driven, no polling)

/// Calls `onChange` whenever the power source or battery percentage changes.
final class PowerSourceObserver {
    private var source: CFRunLoopSource?
    private static var handler: (() -> Void)?

    func start(_ onChange: @escaping () -> Void) {
        Self.handler = onChange
        guard source == nil,
              let src = IOPSNotificationCreateRunLoopSource({ _ in PowerSourceObserver.handler?() }, nil)?
                  .takeRetainedValue()
        else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        source = src
    }
}

// MARK: - Lid (clamshell) open/close events

final class ClamshellMonitor {
    /// iokit_family_msg(sub_iokit_powermanagement, 0x100) — kIOPMMessageClamshellStateChange
    private static let clamshellMessage: UInt32 = 0xE003_4100
    private static var handler: ((Bool) -> Void)?
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0

    func start(_ onChange: @escaping (_ closed: Bool) -> Void) {
        Self.handler = onChange
        guard port == nil else { return }
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return }
        defer { IOObjectRelease(root) }
        port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, .main)
        IOServiceAddInterestNotification(port, root, kIOGeneralInterest, { _, _, type, arg in
            guard type == ClamshellMonitor.clamshellMessage else { return }
            let closed = (Int(bitPattern: arg) & 1) == 1 // kClamshellStateBit
            ClamshellMonitor.handler?(closed)
        }, nil, &notifier)
    }

    static func isClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let v = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (v as? Bool) ?? false
    }
}

// MARK: - Screen lock

enum ScreenLock {
    private typealias LockFn = @convention(c) () -> Int32

    private static var lockFunction: LockFn? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let sym = dlsym(h, "SACLockScreenImmediate")
        else { return nil }
        return unsafeBitCast(sym, to: LockFn.self)
    }()

    static var isAvailable: Bool { lockFunction != nil }

    /// Locks the screen immediately (same as ⌃⌘Q). Falls back to sleeping the display.
    static func lock() {
        if let fn = lockFunction {
            _ = fn()
        } else {
            SleepControl.run("/usr/bin/pmset", ["displaysleepnow"])
        }
    }
}

// MARK: - Global hot key (⌥⌘A) — Carbon, needs no Accessibility permission

final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static var action: (() -> Void)?

    func register(_ action: @escaping () -> Void) {
        Self.action = action
        guard ref == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotKey.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4157_4D43), id: 1) // 'AWMC'
        RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        ref = nil
        handlerRef = nil
    }
}

// MARK: - Process list and network counters (only sampled while a trigger needs them)

enum ProcessList {
    static func names() -> Set<String> {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var result = Set<String>()
        var buf = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(max(0, filled))) where pid > 0 {
            if proc_name(pid, &buf, UInt32(buf.count)) > 0 {
                result.insert(String(cString: buf).lowercased())
            }
        }
        return result
    }
}

enum NetworkCounter {
    /// Total bytes in+out over physical interfaces (en*), from getifaddrs.
    static func totalBytes() -> UInt64 {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return 0 }
        defer { freeifaddrs(head) }
        var total: UInt64 = 0
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = p {
            let name = String(cString: ifa.pointee.ifa_name)
            if name.hasPrefix("en"), let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               let data = ifa.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                total += UInt64(data.pointee.ifi_ibytes) + UInt64(data.pointee.ifi_obytes)
            }
            p = ifa.pointee.ifa_next
        }
        return total
    }
}

enum Displays {
    static var hasExternal: Bool {
        NSScreen.screens.contains { screen in
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(n.uint32Value) == 0
        }
    }
}
