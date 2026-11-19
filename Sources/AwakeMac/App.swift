import AppKit
import Combine
import SwiftUI

@main
struct AwakeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The UI lives in an NSPopover owned by StatusBarController (it grows
    // downward from the menu bar, unlike MenuBarExtra's window).
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let controller: AwakeController
    private var cancellable: AnyCancellable?

    init(controller: AwakeController) {
        self.controller = controller
        super.init()
        let host = NSHostingController(rootView: MenuContentView().environmentObject(controller))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true

        item.button?.target = self
        item.button?.action = #selector(toggle(_:))
        cancellable = controller.$mode.sink { [weak self] mode in self?.setIcon(mode) }
    }

    private func setIcon(_ mode: AwakeMode) {
        let image = NSImage(systemSymbolName: mode.menuBarSymbol, accessibilityDescription: "Awake Mac: \(mode.title)")
        image?.isTemplate = true
        item.button?.image = image
    }

    @objc private func toggle(_ sender: Any?) {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            controller.refreshSystemState()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated { Snapshot.render(to: args[i + 1]) }
            exit(0)
        }

        MainActor.assumeIsolated {
            AwakeController.shared.bootstrap()
            statusBar = StatusBarController(controller: AwakeController.shared)
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

    func applicationWillTerminate(_ notification: Notification) {
        AwakeController.restoreSystemDefaults()
    }
}
