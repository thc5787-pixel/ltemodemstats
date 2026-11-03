import Foundation
@testable import ModemCore
import Testing

@Test func fixtureLoads() {
    #expect(Fixture.qdc507.count >= 18)
    #expect(Fixture.lines("AT+CSQ") == ["+CSQ: 30,99"])
}

// MARK: - Device / SIM

@Test func parsesDeviceValues() {
    #expect(ATParsers.bareValue(Fixture.lines("AT+CGMM")) == "QDC507")
    #expect(ATParsers.bareValue(Fixture.lines("AT+QGMR")) == "QDC507GLEFM21_01.001.02.004")
    #expect(ATParsers.imei(Fixture.lines("AT+GSN")) == "863000000000252")
    #expect(ATParsers.temperature(Fixture.lines("AT+QTEMP")) == 51)
}

@Test func parsesSIM() {
    #expect(ATParsers.simState(Fixture.lines("AT+CPIN?")) == .ready)
    #expect(ATParsers.simState(["+CPIN: SIM PIN"]) == .pinRequired)
    #expect(ATParsers.simState(error: "+CME ERROR: 10") == .notInserted)
    #expect(ATParsers.simState(error: "+CME ERROR: 13") == .error)
    #expect(ATParsers.imsi(Fixture.lines("AT+CIMI")) == "460000000000859")
    #expect(ATParsers.iccid(Fixture.lines("AT+QCCID")) == "89860300000000009420")
    #expect(ATParsers.iccid(["+QCCID: 8986030000000000942F"]) == "8986030000000000942")
    #expect(ATParsers.phoneNumber(Fixture.lines("AT+CNUM")) == "+8613800000000")
    #expect(ATParsers.phoneNumber([]) == nil)
}

// MARK: - Network

@Test func parsesOperator() {
    let info = ATParsers.operatorInfo(Fixture.lines("AT+COPS?"))
    #expect(info.name == "CHN-CT")
    #expect(info.generation == .lte)
    let none = ATParsers.operatorInfo(["+COPS: 0"])
    #expect(none.name == nil)
    #expect(none.generation == .none)
}

@Test func parsesRegistration() {
    #expect(ATParsers.registration(Fixture.lines("AT+CEREG?")) == .home)
    #expect(ATParsers.registration(Fixture.lines("AT+CREG?"), prefix: "+CREG") == .notRegistered)
    #expect(ATParsers.registration(["+CEREG: 2,5,\"1F2E\",\"1A2B3C\",7"]) == .roaming)
    #expect(ATParsers.registration(["+CREG: 0,3"], prefix: "+CREG") == .denied)
}

@Test func lastMatchingLineWins() {
    // An unsolicited "+CEREG: 1" ahead of the query reply must not be parsed as the reply.
    #expect(ATParsers.registration(["+CEREG: 1", "+CEREG: 0,1"]) == .home)
    #expect(ATParsers.registration(["+CEREG: 5", "+CEREG: 0,2"]) == .searching)
}

@Test func parsesNetworkMode() {
    #expect(ATParsers.networkMode(Fixture.lines("AT+QNWINFO")) ==
        .init(mode: "FDD LTE", plmn: "46011", band: "LTE BAND 3", channel: 1800))
    #expect(ATParsers.networkMode(["+QNWINFO: No Service"]) == nil)
}

@Test func parsesLTEServingCell() throws {
    let cell = try #require(ATParsers.servingCell(Fixture.lines("AT+QENG=\"servingcell\"")))
    #expect(cell == .init(
        state: "NOCONN", isLTE: true, cellID: "1A2B3C", pci: 366, earfcn: 1800, band: 3,
        bandwidthMHz: 20, tac: "1F2E", rsrp: -83, rsrq: -10, rssi: -51, sinr: 13
    ))
}

@Test func servingCellWhileSearching() {
    let cell = ATParsers.servingCell(["+QENG: \"servingcell\",\"SEARCH\""])
    #expect(cell?.state == "SEARCH")
    #expect(cell?.isLTE == false)
    #expect(cell?.rsrp == nil)
}

@Test func parsesCSQ() {
    #expect(ATParsers.rssi(Fixture.lines("AT+CSQ")) == -53)
    #expect(ATParsers.rssi(["+CSQ: 99,99"]) == nil)
}

// MARK: - Data

@Test func parsesDataContexts() {
    let active = ATParsers.activeContexts(Fixture.lines("AT+CGACT?"))
    #expect(active == [1, 5])
    let apns = ATParsers.apns(Fixture.lines("AT+CGDCONT?"))
    #expect(apns == [1: "CTNET", 3: "CTWAP", 4: "SOS", 5: "ims"])
    let addresses = ATParsers.addresses(Fixture.lines("AT+CGPADDR"))
    #expect(addresses[1]?.ipv4 == "10.0.0.2")
    #expect(addresses[1]?.ipv6 == "240e::1")
    #expect(addresses[3]?.ipv4 == nil)
    #expect(addresses[3]?.ipv6 == nil)

    // ims (cid 5) is active too but must not be picked.
    let data = ATParsers.dataInfo(active: active, apns: apns, addresses: addresses)
    #expect(data == DataInfo(connected: true, apn: "CTNET", ipv4: "10.0.0.2", ipv6: "240e::1"))
    #expect(ATParsers.dataInfo(active: [5], apns: apns, addresses: addresses).connected == false)
}

@Test func convertsDottedIPv6() {
    #expect(ATParsers.ipv6("36.14.0.0.0.0.0.0.0.0.0.0.0.0.0.1") == "240e::1")
    #expect(ATParsers.ipv6("0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0") == nil)
    #expect(ATParsers.ipv6("10.0.0.2") == nil)
}

@Test func signalBars() {
    #expect(SignalInfo(rsrp: -83).bars == 4)
    #expect(SignalInfo(rsrp: -100).bars == 2)
    #expect(SignalInfo(rsrp: -120).bars == 0)
    #expect(SignalInfo(rssi: -80).bars == 3)
    #expect(SignalInfo().bars == 0)
}
