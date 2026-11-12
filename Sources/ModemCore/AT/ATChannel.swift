import Foundation
import os

public struct ATResponse: Sendable, Equatable {
    /// Result lines, without echo, final status and unsolicited codes.
    public let lines: [String]
    public let isOK: Bool
    /// The final error line (`ERROR`, `+CME ERROR: …`) when `isOK` is false.
    public let errorMessage: String?
}

public enum ATError: LocalizedError, Equatable {
    case deviceNotFound
    case busy
    case notConnected(String)
    case timeout(command: String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: ATTransportError.deviceNotFound.errorDescription
        case .busy: ATTransportError.busy.errorDescription
        case let .notConnected(message): message
        case let .timeout(command): L10n.t("模块未响应 \(command)。", "No reply from the modem to \(command).")
        }
    }
}

/// Serializes access to the modem's AT interface and turns the byte stream
/// into line-oriented responses. Blocking; call it off the main thread.
public final class ATChannel: @unchecked Sendable {
    private let transport: ATTransport
    private let lock = NSLock()
    /// Set after a timeout: the late reply may still arrive and must not be
    /// mistaken for the next command's result.
    private var needsResync = false
    /// Received bytes not yet consumed: the rest of a chunk after a final result
    /// belongs to the next reply (during a resync, the probe's own reply).
    private var pending = Data()
    /// Set by `shutdown()`; read without `lock` so an in-flight command can see it.
    private let isShutDown = OSAllocatedUnfairLock(initialState: false)
    /// Set by `suspend()`: commands fail with `.busy` until `resume()`.
    private let isSuspended = OSAllocatedUnfairLock(initialState: false)

    /// Sent after a timeout. Its reply carries a `+CMEE:` line, so it can't be confused
    /// with the late `OK`/`ERROR` of the command that timed out.
    static let resyncProbe = "AT+CMEE?"

    public init(transport: ATTransport = USBATTransport()) {
        self.transport = transport
    }

    /// Opens the interface and turns command echo off.
    public func open() throws {
        try lock.withLock {
            try openLocked()
        }
    }

    /// Releases the interface; the next command reopens it.
    public func close() {
        lock.withLock { transport.close() }
    }

    /// Releases the interface for good. An in-flight command stops at its next read instead of
    /// running to its timeout, and no later command reopens the interface. Waits at most
    /// `timeout` for the in-flight command; process exit releases the interface anyway.
    public func shutdown(timeout: TimeInterval = 1) {
        isShutDown.withLock { $0 = true }
        if lock.lock(before: Date().addingTimeInterval(timeout)) {
            transport.close()
            lock.unlock()
        }
    }

    /// Lends the interface to another process: an in-flight command stops at its next read,
    /// the interface is released, and later commands fail with `.busy` until `resume()`.
    /// Returns at once; the release completes in the background.
    public func suspend() {
        isSuspended.withLock { $0 = true }
        DispatchQueue.global(qos: .utility).async { [self] in
            lock.withLock {
                // `resume()` may already have run; then leave the interface open.
                if isSuspended.withLock({ $0 }) { transport.close() }
            }
        }
    }

    public func resume() {
        isSuspended.withLock { $0 = false }
    }

    @discardableResult
    public func execute(_ command: String, timeout: TimeInterval = 5) throws -> ATResponse {
        try lock.withLock {
            try checkUsable()
            if !transport.isOpen {
                try openLocked()
            }
            if needsResync, try !resyncLocked() {
                // Still no reply: don't queue another command behind the stuck one.
                throw ATError.timeout(command: command)
            }
            return try executeLocked(command, timeout: timeout)
        }
    }

    /// After a timeout, waits until the modem answers again and its stale replies are gone.
    /// Returns false if it still doesn't answer; the next command tries again. Throws only
    /// when the interface is lost. Without a pending timeout this does nothing.
    @discardableResult
    public func resync(timeout: TimeInterval = 2) throws -> Bool {
        try lock.withLock {
            try checkUsable()
            guard needsResync, transport.isOpen else { return true }
            return try resyncLocked(timeout: timeout)
        }
    }

    // MARK: - Private (lock held)

    private func checkUsable() throws {
        if isShutDown.withLock({ $0 }) {
            throw ATError.notConnected(L10n.t("AT 接口已关闭。", "AT interface closed."))
        }
        if isSuspended.withLock({ $0 }) {
            throw ATError.busy
        }
    }

    /// Sends `resyncProbe` and reads final results until one carries the probe's own
    /// `+CMEE:` line. Everything before it (late replies of the timed-out command) is dropped.
    private func resyncLocked(timeout: TimeInterval = 2) throws -> Bool {
        try write(Self.resyncProbe)
        let deadline = Date().addingTimeInterval(timeout)
        while deadline.timeIntervalSinceNow > 0 {
            guard let response = try readResponse(for: Self.resyncProbe, until: deadline) else { break }
            if response.lines.contains(where: { $0.hasPrefix("+CMEE:") }) {
                needsResync = false
                try drainInput()
                return true
            }
        }
        needsResync = true
        return false
    }

    private func openLocked() throws {
        do {
            try transport.open()
        } catch ATTransportError.deviceNotFound {
            throw ATError.deviceNotFound
        } catch ATTransportError.busy {
            throw ATError.busy
        } catch {
            throw ATError.notConnected(error.localizedDescription)
        }
        // A previous user of the interface may have left a late reply behind.
        try drainInput()
        _ = try? executeLocked("ATE0", timeout: 2)
    }

    /// Maps a transport failure: if the modem is gone, say so rather than echo an I/O error.
    private func connectionError(_ error: Error) -> ATError {
        transport.close()
        if !transport.isDevicePresent { return .deviceNotFound }
        return .notConnected(error.localizedDescription)
    }

    private func read(timeout: TimeInterval) throws -> Data? {
        do {
            return try transport.read(maxLength: 4096, timeout: timeout)
        } catch {
            throw connectionError(error)
        }
    }

    private func write(_ command: String) throws {
        do {
            try transport.write(Data((command + "\r").utf8), timeout: 2)
        } catch {
            throw connectionError(error)
        }
    }

    private func executeLocked(_ command: String, timeout: TimeInterval) throws -> ATResponse {
        try write(command)
        if let response = try readResponse(for: command, until: Date().addingTimeInterval(timeout)) {
            return response
        }
        needsResync = true
        throw ATError.timeout(command: command)
    }

    /// Reads up to the next final result (`OK`, `ERROR`, `+CME ERROR`); nil at `deadline`.
    /// Bytes after the final result stay unread for the next call.
    private func readResponse(for command: String, until deadline: Date) throws -> ATResponse? {
        let ownPrefix = Self.resultPrefix(of: command)
        var lines: [String] = []

        while true {
            while let newline = pending.firstIndex(of: 0x0A) {
                let lineData = pending[pending.startIndex ..< newline]
                pending.removeSubrange(pending.startIndex ... newline)
                let line = String(decoding: lineData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty || line == command { continue }

                if line == "OK" {
                    return ATResponse(lines: lines, isOK: true, errorMessage: nil)
                }
                if line == "ERROR" || line.hasPrefix("+CME ERROR") || line.hasPrefix("+CMS ERROR") {
                    return ATResponse(lines: lines, isOK: false, errorMessage: line)
                }
                if Self.isUnsolicited(line, ownPrefix: ownPrefix) { continue }
                lines.append(line)
            }
            guard Date() < deadline else { return nil }
            try checkUsable()
            let remaining = max(0.02, deadline.timeIntervalSinceNow)
            if let chunk = try read(timeout: min(0.25, remaining)) {
                pending.append(chunk)
            }
        }
    }

    /// Discards stale bytes (late replies, unsolicited codes). Only after opening and after a
    /// timeout: on a healthy line every reply is consumed by its own command.
    private func drainInput() throws {
        pending.removeAll()
        for _ in 0 ..< 8 {
            guard try read(timeout: 0.03) != nil else { break }
        }
    }

    /// `AT+CSQ` → `+CSQ`, `AT+QENG="servingcell"` → `+QENG`.
    static func resultPrefix(of command: String) -> String? {
        guard command.uppercased().hasPrefix("AT+") else { return nil }
        let body = command.dropFirst(2)
        let end = body.firstIndex(where: { $0 == "=" || $0 == "?" }) ?? body.endIndex
        return String(body[..<end]).uppercased()
    }

    /// For `AT+XXX` commands any `+YYY:` line that isn't `+XXX` is not part of the reply.
    /// Bare-word codes (`RING`, `RDY`, …) never are.
    static func isUnsolicited(_ line: String, ownPrefix: String?) -> Bool {
        if let ownPrefix, line.hasPrefix("+") {
            return !line.hasPrefix(ownPrefix + ":")
        }
        return isURC(line)
    }

    static func isURC(_ line: String) -> Bool {
        let prefixes = [
            "+CMTI:", "+CMT:", "+CDS:", "+CBM:", "RING", "+CRING:", "+CLIP:",
            "NO CARRIER", "BUSY", "SMS DONE", "PB DONE", "RDY", "+CPIN: READY",
            "+QIND:", "+QUSIM:", "+QUSBIND:", "+QIURC:", "+CGEV:", "+CREG:", "+CEREG:", "+CGREG:",
        ]
        return prefixes.contains { line.hasPrefix($0) }
    }
}
