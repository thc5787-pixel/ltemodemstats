import CUSBAT
import Foundation

/// Raw byte pipe to the modem's AT interface. `ATChannel` serializes all calls.
public protocol ATTransport: AnyObject {
    var isOpen: Bool { get }
    /// Whether the modem is still on the bus; used to tell "unplugged" from other I/O errors.
    var isDevicePresent: Bool { get }
    func open() throws
    func close()
    func write(_ data: Data, timeout: TimeInterval) throws
    /// Returns up to `maxLength` bytes, or nil when nothing arrived before `timeout`.
    /// Throws on a transfer error (device gone, pipe stalled), which is not "no data yet".
    func read(maxLength: Int, timeout: TimeInterval) throws -> Data?
}

public enum ATTransportError: LocalizedError, Equatable {
    /// No QDC507 on the USB bus.
    case deviceNotFound
    /// The module is present but another process holds the AT interface.
    case busy
    case openFailed(String)
    case notOpen
    case writeFailed(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: L10n.t("未检测到模块（2c7c:0125）。", "Modem not found (2c7c:0125).")
        case .busy: L10n.t("模块 AT 接口被其他程序占用。", "The modem's AT interface is in use by another program.")
        case let .openFailed(message): L10n.t("无法打开模块 AT 接口：\(message)", "Cannot open the AT interface: \(message)")
        case .notOpen: L10n.t("模块 AT 接口未连接。", "The modem's AT interface is not open.")
        case let .writeFailed(message): L10n.t("模块 AT 写入失败：\(message)", "AT write failed: \(message)")
        case let .readFailed(message): L10n.t("模块 AT 读取失败：\(message)", "AT read failed: \(message)")
        }
    }
}

/// QDC507 (rewritten as Quectel EC25) vendor interface 2, bulk OUT 0x03 / IN 0x84,
/// opened directly through IOUSBHost. macOS creates no serial device for it.
public final class USBATTransport: ATTransport {
    public static let vendorID: UInt16 = 0x2C7C
    public static let productID: UInt16 = 0x0125
    public static let interfaceNumber: UInt8 = 2
    public static let endpointOut: UInt8 = 0x03
    public static let endpointIn: UInt8 = 0x84

    public private(set) var isOpen = false

    public init() {}

    public var isDevicePresent: Bool {
        usbat_device_present(Self.vendorID, Self.productID, Self.interfaceNumber) == 1
    }

    private var lastError: String {
        var buffer = [CChar](repeating: 0, count: 512)
        usbat_last_error(&buffer, buffer.count)
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    public func open() throws {
        guard !isOpen else { return }
        let result = usbat_open(
            Self.vendorID, Self.productID, Self.interfaceNumber,
            Self.endpointOut, Self.endpointIn
        )
        switch result {
        case 0: break
        case -1: throw ATTransportError.deviceNotFound
        case -2: throw ATTransportError.busy
        default: throw ATTransportError.openFailed(lastError.isEmpty ? "error \(result)" : lastError)
        }
        isOpen = true
    }

    public func close() {
        guard isOpen else { return }
        usbat_close()
        isOpen = false
    }

    public func write(_ data: Data, timeout: TimeInterval) throws {
        guard isOpen else { throw ATTransportError.notOpen }
        let result: Int32 = data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return usbat_write(base, data.count, timeout)
        }
        guard result == data.count else {
            let message = lastError.isEmpty ? "short write" : lastError
            // A partial write leaves the stream misaligned; reopen on the next command.
            close()
            throw ATTransportError.writeFailed(message)
        }
    }

    public func read(maxLength: Int, timeout: TimeInterval) throws -> Data? {
        guard isOpen else { throw ATTransportError.notOpen }
        var buffer = [UInt8](repeating: 0, count: maxLength)
        let result = usbat_read(&buffer, buffer.count, timeout)
        if result < 0 {
            let message = lastError
            close()
            throw ATTransportError.readFailed(message)
        }
        guard result > 0 else { return nil }
        return Data(buffer.prefix(Int(result)))
    }
}
