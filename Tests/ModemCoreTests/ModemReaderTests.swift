import Foundation
@testable import ModemCore
import Testing

@Test func readerBuildsStatusFromFixture() throws {
    let transport = MockTransport()
    transport.replies = Fixture.qdc507.mapValues { lines in
        ["\r\n" + lines.joined(separator: "\r\n") + "\r\n"]
    }
    transport.replies["ATE0"] = ["\r\nOK\r\n"]
    let (status, timedOut) = try ModemReader(channel: ATChannel(transport: transport)).readAll()
    #expect(timedOut.isEmpty)

    #expect(status.device == DeviceInfo(
        manufacturer: "Baiwang", model: "QDC507",
        firmware: "QDC507GLEFM21_01.001.02.004", imei: "863000000000252"
    ))
    #expect(status.sim?.state == .ready)
    #expect(status.sim?.phoneNumber == "+8613800000000")
    #expect(status.network?.operatorName == "CHN-CT")
    #expect(status.network?.registration == .home)
    #expect(status.network?.band == "LTE BAND 3")
    #expect(status.signal == SignalInfo(rsrp: -83, rsrq: -10, sinr: 13, rssi: -51))
    #expect(status.data?.apn == "CTNET")
    #expect(status.temperature == 51)
    // LTE registered: the legacy +CREG query is skipped.
    #expect(!transport.written.contains("AT+CREG?"))
}

@Test func readerKeepsGroupsThatAnsweredWhenOneTimesOut() throws {
    let transport = MockTransport()
    transport.replies = Fixture.qdc507.mapValues { ["\r\n" + $0.joined(separator: "\r\n") + "\r\n"] }
    transport.replies["ATE0"] = ["\r\nOK\r\n"]
    transport.replies["AT+CMEE?"] = ["\r\n+CMEE: 1\r\n\r\nOK\r\n"]
    transport.replies["AT+QENG=\"servingcell\""] = []  // never answers
    let reader = ModemReader(channel: ATChannel(transport: transport), commandTimeout: 0.1)
    var status = ModemStatus()
    let timedOut = try reader.refresh([.radio, .temperature, .data], into: &status)
    #expect(timedOut == [.radio])
    #expect(status.network == nil)
    #expect(status.temperature == 51)
    #expect(status.data?.apn == "CTNET")
}

@Test func readerStopsTheRoundWhenTheModemIsSilent() throws {
    let transport = MockTransport()
    transport.replies = ["ATE0": ["\r\nOK\r\n"]]  // nothing else answers
    let reader = ModemReader(channel: ATChannel(transport: transport), commandTimeout: 0.05)
    var status = ModemStatus()
    let timedOut = try reader.refresh([.sim, .radio, .data, .temperature], into: &status)
    #expect(timedOut == [.sim, .radio, .data, .temperature])
    // One command and one probe, not a timeout per group.
    #expect(transport.written == ["ATE0", "AT+CPIN?", "AT+CMEE?"])
}

@Test func readerSkipsSIMDetailsWithoutCard() throws {
    let transport = MockTransport()
    transport.replies = ["ATE0": ["\r\nOK\r\n"], "AT+CPIN?": ["\r\n+CME ERROR: 10\r\n"]]
    var status = ModemStatus()
    try ModemReader(channel: ATChannel(transport: transport)).refresh([.sim], into: &status)
    #expect(status.sim == SIMInfo(state: .notInserted))
    #expect(!transport.written.contains("AT+CIMI"))
}
