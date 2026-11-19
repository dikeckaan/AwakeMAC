import AppKit
import SwiftUI

@main
struct LidAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AwakeController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(controller)
        } label: {
            Image(systemName: controller.mode.menuBarSymbol)
                .accessibilityLabel("LidAwake: \(controller.mode.title)")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated { Snapshot.render(to: args[i + 1]) }
            exit(0)
        }

        MainActor.assumeIsolated { AwakeController.shared.bootstrap() }

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
