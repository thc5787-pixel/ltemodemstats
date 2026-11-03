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
    /// Set by `shutdown()`; read without `lock` so an in-flight command can see it.
    private let isShutDown = OSAllocatedUnfairLock(initialState: false)

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

    @discardableResult
    public func execute(_ command: String, timeout: TimeInterval = 5) throws -> ATResponse {
        try lock.withLock {
            try checkNotShutDown()
            if !transport.isOpen {
                try openLocked()
            }
            if needsResync {
                needsResync = false
                _ = try? executeLocked("AT", timeout: 1)
                try drainInput()
            }
            return try executeLocked(command, timeout: timeout)
        }
    }

    // MARK: - Private (lock held)

    private func checkNotShutDown() throws {
        if isShutDown.withLock({ $0 }) {
            throw ATError.notConnected(L10n.t("AT 接口已关闭。", "AT interface closed."))
        }
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

    private func executeLocked(_ command: String, timeout: TimeInterval) throws -> ATResponse {
        do {
            try transport.write(Data((command + "\r").utf8), timeout: 2)
        } catch {
            throw connectionError(error)
        }

        let ownPrefix = Self.resultPrefix(of: command)
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        var lines: [String] = []

        while Date() < deadline {
            try checkNotShutDown()
            let remaining = max(0.02, deadline.timeIntervalSinceNow)
            guard let chunk = try read(timeout: min(0.25, remaining)) else { continue }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex ..< newline]
                buffer.removeSubrange(buffer.startIndex ... newline)
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
        }
        needsResync = true
        throw ATError.timeout(command: command)
    }

    /// Discards stale bytes (late replies, unsolicited codes). Only after opening and after a
    /// timeout: on a healthy line every reply is consumed by its own command.
    private func drainInput() throws {
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
