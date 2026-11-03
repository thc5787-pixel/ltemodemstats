import Darwin
import Foundation
import IOKit

/// Bytes moved through a network interface since it came up.
public struct InterfaceCounters: Equatable, Sendable {
    public var rxBytes: UInt64
    public var txBytes: UInt64

    public init(rxBytes: UInt64, txBytes: UInt64) {
        self.rxBytes = rxBytes
        self.txBytes = txBytes
    }
}

public enum NetworkInterfaces {
    /// BSD name (`en8`) of the modem's ECM network interface, found under its USB device node
    /// so it survives renumbering after re-plugging.
    public static func modemInterface(
        vendorID: UInt16 = USBATTransport.vendorID,
        productID: UInt16 = USBATTransport.productID
    ) -> String? {
        let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        matching["idVendor"] = vendorID
        matching["idProduct"] = productID
        // IOServiceGetMatchingService consumes the dictionary reference.
        let device = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard device != 0 else { return nil }
        defer { IOObjectRelease(device) }

        let name = IORegistryEntrySearchCFProperty(
            device, kIOServicePlane, "BSD Name" as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ) as? String
        return name.flatMap { $0.hasPrefix("en") ? $0 : nil }
    }

    /// 64-bit counters from the interface MIB (`net.link.generic.ifdata`), as `netstat -ib` reads them.
    /// `getifaddrs` wraps at 4 GB, and so does `NET_RT_IFLIST2` on current macOS despite its 64-bit fields.
    public static func counters(for name: String) -> InterfaceCounters? {
        let index = if_nametoindex(name)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(index), IFDATA_GENERAL]
        var data = ifmibdata()
        var length = MemoryLayout<ifmibdata>.size
        guard sysctl(&mib, UInt32(mib.count), &data, &length, nil, 0) == 0 else { return nil }
        return InterfaceCounters(rxBytes: data.ifmd_data.ifi_ibytes, txBytes: data.ifmd_data.ifi_obytes)
    }
}
