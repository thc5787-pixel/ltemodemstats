import Foundation

/// Pure parsers for EC25 / QDC507 replies. Each takes `ATResponse.lines`.
public enum ATParsers {
    // MARK: - Helpers

    /// Fields of the last line starting with `prefix` (e.g. `"+CSQ"`), quotes removed.
    /// `+COPS: 0,0,"CHN-CT",7` → `["0", "0", "CHN-CT", "7"]`. The last one, because an
    /// unsolicited code with the same prefix can only arrive before the command's own reply.
    static func fields(_ lines: [String], prefix: String) -> [String]? {
        allFields(lines, prefix: prefix).last
    }

    static func allFields(_ lines: [String], prefix: String) -> [[String]] {
        lines.compactMap { line in
            guard line.hasPrefix(prefix + ":") else { return nil }
            return splitFields(String(line.dropFirst(prefix.count + 1)))
        }
    }

    static func splitFields(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        for character in text {
            switch character {
            case "\"": quoted.toggle()
            case "," where !quoted:
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default: current.append(character)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    /// First non-empty line, for commands that reply with a bare value (`AT+GSN`, `AT+CIMI`).
    static func bareValue(_ lines: [String]) -> String? {
        lines.first { !$0.isEmpty && !$0.hasPrefix("+") }
    }

    private static func int(_ text: String?) -> Int? {
        text.flatMap { Int($0) }
    }

    // MARK: - Device

    public static func imei(_ lines: [String]) -> String? {
        bareValue(lines).flatMap { $0.allSatisfy(\.isNumber) && $0.count >= 14 ? $0 : nil }
    }

    /// `+QTEMP: 51,46,46` → 51 (hottest sensor). Newer firmware sends one
    /// `+QTEMP: "<sensor>","<value>"` line per sensor; the hottest of all lines counts.
    public static func temperature(_ lines: [String]) -> Int? {
        allFields(lines, prefix: "+QTEMP").joined().compactMap { Int($0) }.max()
    }

    // MARK: - SIM

    /// `+CPIN: READY`. A failed `AT+CPIN?` (`+CME ERROR: 10`) means no SIM; see `simState(error:)`.
    public static func simState(_ lines: [String]) -> SIMInfo.State {
        guard let value = fields(lines, prefix: "+CPIN")?.first else { return .error }
        switch value {
        case "READY": return .ready
        case "SIM PIN", "SIM PIN2": return .pinRequired
        case "SIM PUK", "SIM PUK2": return .pukRequired
        default: return .error
        }
    }

    /// `+CME ERROR: 10` (SIM not inserted) / `13` (SIM failure).
    public static func simState(error: String?) -> SIMInfo.State {
        guard let error else { return .error }
        return error.hasSuffix(": 10") || error.localizedCaseInsensitiveContains("not inserted")
            ? .notInserted : .error
    }

    public static func imsi(_ lines: [String]) -> String? {
        bareValue(lines).flatMap { $0.allSatisfy(\.isNumber) ? $0 : nil }
    }

    /// `+QCCID: 8986…` (may end in `F` padding).
    public static func iccid(_ lines: [String]) -> String? {
        guard let value = fields(lines, prefix: "+QCCID")?.first, !value.isEmpty else { return nil }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "Ff"))
    }

    /// `+CNUM: "My Number","+86…",145`; empty reply when the SIM has no number stored.
    public static func phoneNumber(_ lines: [String]) -> String? {
        guard let fields = fields(lines, prefix: "+CNUM"), fields.count >= 2, !fields[1].isEmpty else { return nil }
        return fields[1]
    }

    // MARK: - Network

    /// `+COPS: 0,0,"CHN-CT",7` → ("CHN-CT", .lte); `+COPS: 0` → (nil, .none).
    public static func operatorInfo(_ lines: [String]) -> (name: String?, generation: RadioGeneration) {
        guard let fields = fields(lines, prefix: "+COPS"), fields.count >= 3 else { return (nil, .none) }
        let generation = int(fields.count >= 4 ? fields[3] : nil).map(RadioGeneration.init) ?? .none
        return (fields[2].isEmpty ? nil : fields[2], generation)
    }

    /// `+CEREG: <n>,<stat>[,<tac>,<ci>,<AcT>]` (same layout for `+CREG`).
    public static func registration(_ lines: [String], prefix: String = "+CEREG") -> Registration {
        guard let fields = fields(lines, prefix: prefix), fields.count >= 2,
              let stat = Int(fields[1]) else { return .unknown }
        return Registration(stat: stat)
    }

    public struct NetworkMode: Equatable, Sendable {
        public var mode: String
        public var plmn: String?
        public var band: String?
        public var channel: Int?
    }

    /// `+QNWINFO: "FDD LTE","46011","LTE BAND 3",1800`; `+QNWINFO: No Service` → nil.
    public static func networkMode(_ lines: [String]) -> NetworkMode? {
        guard let fields = fields(lines, prefix: "+QNWINFO"), fields.count >= 4 else { return nil }
        return NetworkMode(mode: fields[0], plmn: fields[1], band: fields[2], channel: Int(fields[3]))
    }

    public struct ServingCell: Equatable, Sendable {
        public var state: String
        public var isLTE: Bool
        public var cellID: String?
        public var pci: Int?
        public var earfcn: Int?
        public var band: Int?
        public var bandwidthMHz: Double?
        public var tac: String?
        public var rsrp: Int?
        public var rsrq: Int?
        public var rssi: Int?
        public var sinr: Int?
    }

    /// EC25 LTE layout:
    /// `+QENG: "servingcell",<state>,"LTE",<is_tdd>,<MCC>,<MNC>,<cellID>,<PCID>,<earfcn>,<band>,
    /// <UL_bw>,<DL_bw>,<TAC>,<RSRP>,<RSRQ>,<RSSI>,<SINR>,<srxlev>`.
    /// Other RATs and `"SEARCH"` only fill `state`.
    public static func servingCell(_ lines: [String]) -> ServingCell? {
        guard let fields = fields(lines, prefix: "+QENG"), fields.count >= 2,
              fields[0] == "servingcell" else { return nil }
        var cell = ServingCell(state: fields[1], isLTE: false)
        guard fields.count >= 17, fields[2] == "LTE" else { return cell }
        cell.isLTE = true
        cell.cellID = fields[6]
        cell.pci = int(fields[7])
        cell.earfcn = int(fields[8])
        cell.band = int(fields[9])
        cell.bandwidthMHz = int(fields[11]).flatMap(lteBandwidth)
        cell.tac = fields[12]
        cell.rsrp = int(fields[13])
        cell.rsrq = int(fields[14])
        cell.rssi = int(fields[15])
        // This firmware reports SINR in dB (consistent with its RSRQ), not the 1/5 dB raw scale.
        cell.sinr = int(fields[16])
        return cell
    }

    /// 3GPP bandwidth index 0…5 → MHz.
    static func lteBandwidth(_ index: Int) -> Double? {
        let table: [Double] = [1.4, 3, 5, 10, 15, 20]
        return table.indices.contains(index) ? table[index] : nil
    }

    /// `+CSQ: 30,99` → -53 dBm; 99 = unknown.
    public static func rssi(_ lines: [String]) -> Int? {
        guard let value = int(fields(lines, prefix: "+CSQ")?.first), (0 ... 31).contains(value) else { return nil }
        return -113 + 2 * value
    }

    // MARK: - Data

    /// `+CGACT: 1,1` lines → cids whose context is active.
    public static func activeContexts(_ lines: [String]) -> Set<Int> {
        Set(allFields(lines, prefix: "+CGACT").compactMap { fields in
            fields.count >= 2 && fields[1] == "1" ? Int(fields[0]) : nil
        })
    }

    /// `+CGDCONT: 1,"IPV4V6","CTNET",…` → [1: "CTNET"].
    public static func apns(_ lines: [String]) -> [Int: String] {
        var result: [Int: String] = [:]
        for fields in allFields(lines, prefix: "+CGDCONT") where fields.count >= 3 {
            if let cid = Int(fields[0]) { result[cid] = fields[2] }
        }
        return result
    }

    /// `+CGPADDR: 1,"10.0.0.2,36.14.…"` → [1: ("10.0.0.2", "240e:…")]. All-zero addresses are dropped.
    public static func addresses(_ lines: [String]) -> [Int: (ipv4: String?, ipv6: String?)] {
        var result: [Int: (ipv4: String?, ipv6: String?)] = [:]
        for fields in allFields(lines, prefix: "+CGPADDR") where fields.count >= 2 {
            guard let cid = Int(fields[0]) else { continue }
            var entry: (ipv4: String?, ipv6: String?) = (nil, nil)
            // The address field may hold "v4,v6" inside one quoted string, or two fields.
            for part in fields.dropFirst().flatMap({ $0.split(separator: ",").map(String.init) }) {
                if let v4 = ipv4(part) { entry.ipv4 = v4 } else if let v6 = ipv6(part) { entry.ipv6 = v6 }
            }
            result[cid] = entry
        }
        return result
    }

    static func ipv4(_ text: String) -> String? {
        let octets = text.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4, text.split(separator: ".").count == 4, octets != [0, 0, 0, 0] else { return nil }
        return text
    }

    /// The modem writes IPv6 as 16 dotted decimal bytes; also accepts standard notation.
    static func ipv6(_ text: String) -> String? {
        if text.contains(":") { return text }
        let parts = text.split(separator: ".")
        let bytes = parts.compactMap { UInt8($0) }
        guard parts.count == 16, bytes.count == 16, bytes.contains(where: { $0 != 0 }) else { return nil }
        var address = in6_addr()
        withUnsafeMutableBytes(of: &address) { $0.copyBytes(from: bytes) }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        let text = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: text, as: UTF8.self)
    }

    /// Picks the internet context: active, not IMS/emergency, lowest cid.
    public static func dataInfo(active: Set<Int>, apns: [Int: String],
                                addresses: [Int: (ipv4: String?, ipv6: String?)]) -> DataInfo {
        let service = ["ims", "sos"]
        let cid = active.filter { !service.contains(apns[$0]?.lowercased() ?? "") }.min()
        guard let cid else { return DataInfo(connected: false) }
        let address = addresses[cid]
        return DataInfo(connected: true, apn: apns[cid], ipv4: address?.ipv4, ipv6: address?.ipv6)
    }
}
