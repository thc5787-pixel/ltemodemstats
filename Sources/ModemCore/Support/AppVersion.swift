import Foundation

/// Version from the app's Info.plist (written by Scripts/build.sh from the VERSION file).
public enum AppVersion {
    /// `1.0.0`, or nil outside an app bundle (a plain `swift build`).
    public static let short: String? = values.short
    /// Build timestamp, e.g. `202611031829`.
    public static let build: String? = values.build

    /// `1.0.0 (202611031829)`, or `dev` for an unbundled build.
    public static var display: String {
        guard let short else { return "dev" }
        return build.map { "\(short) (\($0))" } ?? short
    }

    /// Read from Bundle.main's Info.plist; when run through a symlink (~/.local/bin), from the
    /// app the real executable lives in.
    private static let values: (short: String?, build: String?) = {
        var info = Bundle.main.infoDictionary
        if info?["CFBundleShortVersionString"] == nil {
            let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
            let plist = URL(fileURLWithPath: executable).resolvingSymlinksInPath()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Info.plist")
            info = NSDictionary(contentsOf: plist) as? [String: Any]
        }
        return (info?["CFBundleShortVersionString"] as? String, info?["CFBundleVersion"] as? String)
    }()
}
