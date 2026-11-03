import Foundation
import ServiceManagement

/// Start at login as a login item of the .app (System Settings › General › Login Items).
public protocol LoginItem: Sendable {
    var isEnabled: Bool { get }
    /// Registered, but the user still has to allow it in System Settings.
    var needsApproval: Bool { get }
    func enable() throws
    func disable() throws
}

/// `SMAppService.mainApp`. Only works when running from the .app bundle.
public struct AppLoginItem: LoginItem {
    public init() {}

    public var isEnabled: Bool {
        [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
    }

    public var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    public func enable() throws {
        try SMAppService.mainApp.register()
    }

    public func disable() throws {
        // unregister() throws when there is nothing registered.
        if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }

    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
