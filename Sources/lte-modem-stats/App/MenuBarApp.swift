import AppKit
import ModemCore

/// Menu-bar-only process: no Dock icon, no windows besides the popover.
@MainActor
final class MenuBarApp: NSObject, NSApplicationDelegate {
    private var service: ModemService?
    private var controller: StatusItemController?
    private var signalSources: [DispatchSourceSignal] = []

    /// Kept alive for the life of the process (`NSApplication.delegate` is weak).
    private static var shared: MenuBarApp?

    static func run() -> Never {
        guard acquireSingleInstanceLock() else {
            FileHandle.standardError.write(Data(L10n.t("LTE Modem Stats 已在运行。\n", "LTE Modem Stats is already running.\n").utf8))
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = MenuBarApp()
        shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let service = ModemService(settings: AppSettings())
        self.service = service
        controller = StatusItemController(service: service)
        service.start()
        handleTerminationSignals()
    }

    func applicationWillTerminate(_ notification: Notification) {
        service?.stop()
    }

    /// launchd stops agents with SIGTERM; route it (and Ctrl-C) through a normal
    /// termination so traffic history is saved and the AT interface released.
    private func handleTerminationSignals() {
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Holds an exclusive lock for the life of the process; a second instance fails to get it.
    private static func acquireSingleInstanceLock() -> Bool {
        let directory = TrafficHistory.defaultURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("menubar.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return true }
        // The descriptor is intentionally never closed; the lock dies with the process.
        return flock(descriptor, LOCK_EX | LOCK_NB) == 0
    }
}
