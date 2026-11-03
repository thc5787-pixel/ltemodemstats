import Foundation
@testable import ModemCore
import Testing

/// In-memory login item; `failure` makes enable/disable throw.
private final class FakeLoginItem: LoginItem, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    var approvalRequired = false
    var failure: Error?

    var isEnabled: Bool { lock.withLock { enabled } }
    var needsApproval: Bool { lock.withLock { enabled && approvalRequired } }

    func enable() throws {
        if let failure { throw failure }
        lock.withLock { enabled = true }
    }

    func disable() throws {
        if let failure { throw failure }
        lock.withLock { enabled = false }
    }
}

private struct TestFailure: LocalizedError {
    var errorDescription: String? { "not allowed" }
}

/// A throwaway UserDefaults suite, removed when the closure returns.
private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "lte-modem-stats-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
}

@MainActor
@Test func launchAtLoginToggleDrivesLoginItem() throws {
    try withDefaults { defaults in
        let item = FakeLoginItem()
        let settings = AppSettings(defaults: defaults, loginItem: item)
        #expect(!settings.launchAtLogin)

        settings.launchAtLogin = true
        #expect(item.isEnabled)
        #expect(settings.launchAtLoginError == nil)
        // A new settings object reads the state back from the system, not from defaults.
        #expect(AppSettings(defaults: defaults, loginItem: item).launchAtLogin)

        settings.launchAtLogin = false
        #expect(!item.isEnabled)
    }
}

@MainActor
@Test func launchAtLoginFailureIsReportedAndReverted() throws {
    try withDefaults { defaults in
        let item = FakeLoginItem()
        item.failure = TestFailure()
        let settings = AppSettings(defaults: defaults, loginItem: item)

        settings.launchAtLogin = true
        #expect(!settings.launchAtLogin)
        #expect(settings.launchAtLoginError == "not allowed")
    }
}

@MainActor
@Test func launchAtLoginApprovalAndRefresh() throws {
    try withDefaults { defaults in
        let item = FakeLoginItem()
        item.approvalRequired = true
        let settings = AppSettings(defaults: defaults, loginItem: item)

        settings.launchAtLogin = true
        #expect(settings.launchAtLoginNeedsApproval)

        // Turned off in System Settings behind the app's back.
        try item.disable()
        settings.refreshLaunchAtLogin()
        #expect(!settings.launchAtLogin)
        #expect(!settings.launchAtLoginNeedsApproval)
    }
}

@Test func storedBillingDayDefaultsAndClamps() throws {
    try withDefaults { defaults in
        #expect(AppSettings.storedBillingDay(defaults) == 1)
        defaults.set(15, forKey: "billingDay")
        #expect(AppSettings.storedBillingDay(defaults) == 15)
        defaults.set(31, forKey: "billingDay")
        #expect(AppSettings.storedBillingDay(defaults) == 28)
    }
}
