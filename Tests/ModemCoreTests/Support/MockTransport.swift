import Foundation
@testable import ModemCore

/// Replies to each written command with a scripted list of chunks.
final class MockTransport: ATTransport {
    var isOpen = false
    var isDevicePresent = true
    var openError: Error?
    /// Thrown by the next read.
    var readError: Error?
    private(set) var openCount = 0
    var replies: [String: [String]] = [:]
    private(set) var written: [String] = []
    private var pending: [Data] = []

    func open() throws {
        if let openError { throw openError }
        openCount += 1
        isOpen = true
    }

    func close() { isOpen = false }

    func write(_ data: Data, timeout: TimeInterval) throws {
        let command = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
        written.append(command)
        pending += (replies[command] ?? []).map { Data($0.utf8) }
    }

    /// Puts bytes in the input buffer as if the modem had sent them earlier.
    func inject(_ text: String) { pending.append(Data(text.utf8)) }

    func read(maxLength: Int, timeout: TimeInterval) throws -> Data? {
        if let readError {
            self.readError = nil
            throw readError
        }
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }
}

/// `open()` sends `ATE0`; reply to it so tests don't wait for a timeout.
func makeChannel(_ replies: [String: [String]] = [:]) -> (ATChannel, MockTransport) {
    let transport = MockTransport()
    transport.replies = ["ATE0": ["\r\nOK\r\n"]].merging(replies) { $1 }
    return (ATChannel(transport: transport), transport)
}
