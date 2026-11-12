import Foundation

/// Lets the CLI borrow the AT interface from the running menu bar app, which otherwise
/// holds it for as long as it runs. The CLI posts `release`; the app suspends its channel
/// until `done` (or `maxLoan`, in case the CLI dies without saying so).
public enum ATHandoff {
    static let release = Notification.Name("com.ltemodemstats.at.release")
    static let done = Notification.Name("com.ltemodemstats.at.done")
    /// The app takes the interface back after this even without `done`.
    public static let maxLoan: TimeInterval = 60

    /// Opens `channel`. If another process holds the interface, asks the menu bar app to
    /// release it and retries for up to `wait`. Call `finish()` when done if this returns true.
    /// - Returns: whether the app was asked to release the interface.
    @discardableResult
    public static func open(_ channel: ATChannel, wait: TimeInterval = 4) throws -> Bool {
        do {
            try channel.open()
            return false
        } catch ATError.busy {}

        post(release)
        let deadline = Date().addingTimeInterval(wait)
        while true {
            Thread.sleep(forTimeInterval: 0.2)
            do {
                try channel.open()
                return true
            } catch ATError.busy where Date() < deadline {
                continue
            } catch {
                // Give the interface back right away instead of after `maxLoan`.
                post(done)
                throw error
            }
        }
    }

    /// Tells the menu bar app it can take the interface back.
    public static func finish() {
        post(done)
    }

    private static func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default()
            .postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
