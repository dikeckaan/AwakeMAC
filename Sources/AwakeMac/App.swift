import AppKit
import Combine
import SwiftUI

@main
struct AwakeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The UI lives in an NSPopover owned by StatusBarController (it grows
    // downward from the menu bar) and in windows owned by WindowManager.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - Status item

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let controller: AwakeController
    private let prefs = Prefs.shared
    private var cancellables: Set<AnyCancellable> = []
    private var titleTimer: Timer?
    private let hotKey = GlobalHotKey()

    init(controller: AwakeController) {
        self.controller = controller
        super.init()
        let host = NSHostingController(
            rootView: MenuContentView()
                .environmentObject(controller)
                // Keep content pinned to the top while the popover resizes.
                .frame(maxHeight: .infinity, alignment: .top)
        )
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        controller.$mode.combineLatest(controller.$endDate, prefs.$showTimeInMenuBar)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.updateButton() }
            .store(in: &cancellables)
        prefs.$hotkeyEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] on in
                guard let self else { return }
                if on { self.hotKey.register { AwakeController.shared.toggle() } } else { self.hotKey.unregister() }
            }
            .store(in: &cancellables)
    }

    private func updateButton() {
        guard let button = item.button else { return }
        let mode = controller.mode
        let image = NSImage(systemSymbolName: mode.menuBarSymbol, accessibilityDescription: "Awake Mac: \(mode.title)")
        image?.isTemplate = true
        button.image = image

        titleTimer?.invalidate()
        titleTimer = nil
        if prefs.showTimeInMenuBar, mode != .off, let end = controller.endDate {
            button.title = " " + compactRemaining(end.timeIntervalSinceNow)
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            // Minute resolution is enough; generous tolerance lets macOS coalesce wake-ups.
            let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateButton() }
            }
            t.tolerance = 10
            RunLoop.main.add(t, forMode: .common)
            titleTimer = t
        } else {
            button.title = ""
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showQuickMenu()
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            controller.refreshSystemState()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: Right-click quick menu

    private func showQuickMenu() {
        let menu = NSMenu()
        menu.delegate = self
        for m in AwakeMode.allCases {
            let mi = NSMenuItem(title: m.title, action: #selector(pickMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = m.rawValue
            mi.state = controller.mode == m ? .on : .off
            mi.image = NSImage(systemSymbolName: m.menuBarSymbol, accessibilityDescription: nil)
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        let durationTitle = NSMenuItem(title: L("section.duration"), action: nil, keyEquivalent: "")
        durationTitle.isEnabled = false
        menu.addItem(durationTitle)
        for d in AwakeDuration.allCases {
            let mi = NSMenuItem(title: d.title, action: #selector(pickDuration(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = d.rawValue
            mi.state = prefs.duration == d ? .on : .off
            mi.indentationLevel = 1
            menu.addItem(mi)
        }
        if controller.mode != .off {
            let ext = NSMenuItem(title: L("duration.extend30"), action: #selector(extend30), keyEquivalent: "")
            ext.target = self
            menu.addItem(ext)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: L("settings.open") + "…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: L("quit"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        item.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        item.menu = nil // restore left-click popover behaviour
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = AwakeMode(rawValue: raw) { controller.select(m) }
    }

    @objc private func pickDuration(_ sender: NSMenuItem) {
        if let d = AwakeDuration(rawValue: sender.tag) { prefs.duration = d }
    }

    @objc private func extend30() { controller.extend(by: 1800) }
    @objc private func openSettings() { WindowManager.shared.showSettings() }
    @objc private func quitApp() { NSApp.terminate(nil) }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []
    private var statusBar: StatusBarController?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated { Snapshot.render(to: args[i + 1]) }
            exit(0)
        }

        MainActor.assumeIsolated {
            AwakeController.shared.bootstrap()
            statusBar = StatusBarController(controller: AwakeController.shared)
            if !Prefs.shared.onboardingDone { WindowManager.shared.showOnboarding() }
            for url in pendingURLs { handle(url) }
            pendingURLs.removeAll()
        }

        // Always undo `disablesleep` when we are asked to stop — even via kill/SIGTERM.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                AwakeController.restoreSystemDefaults()
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { _ in
            AwakeController.restoreSystemDefaults()
        }
    }

    /// awakemac:// URLs (see `URLCommand`).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard statusBar != nil else { pendingURLs += urls; return }
        MainActor.assumeIsolated { urls.forEach(handle) }
    }

    @MainActor private func handle(_ url: URL) {
        if let cmd = URLCommand(url: url) { AwakeController.shared.handle(cmd) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AwakeController.restoreSystemDefaults()
    }
}
