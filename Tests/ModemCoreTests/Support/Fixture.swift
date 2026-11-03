import Foundation

/// Replies captured from the real QDC507 (`lte-modem-stats at …`), keyed by command.
/// Values are the result lines; the final `OK`/`ERROR` is the last element.
enum Fixture {
    static let qdc507: [String: [String]] = load("qdc507.txt")

    static func load(_ name: String) -> [String: [String]] {
        // Tests/ModemCoreTests/Support/Fixture.swift → Tests/ModemCoreTests/Fixtures/<name>
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var result: [String: [String]] = [:]
        var command: String?
        for line in text.split(separator: "\n").map(String.init) {
            if line.hasPrefix("> ") {
                command = String(line.dropFirst(2))
                result[command!] = []
            } else if let command {
                result[command]!.append(line)
            }
        }
        return result
    }

    /// Result lines without the final status, as `ATResponse.lines` would hold them.
    static func lines(_ command: String) -> [String] {
        let all = qdc507[command] ?? []
        return Array(all.dropLast())
    }
}
