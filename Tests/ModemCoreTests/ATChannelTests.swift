import Foundation
@testable import ModemCore
import Testing

@Test func parsesOKResponse() throws {
    let (channel, _) = makeChannel(["AT+CSQ": ["\r\n+CSQ: 23,99\r\n", "\r\nOK\r\n"]])
    let response = try channel.execute("AT+CSQ")
    #expect(response == ATResponse(lines: ["+CSQ: 23,99"], isOK: true, errorMessage: nil))
}

@Test func joinsLinesSplitAcrossReads() throws {
    let (channel, _) = makeChannel(["AT+QNWINFO": ["\r\n+QNWINFO: \"FDD LTE\",\"46011\",", "\"LTE BAND 3\",1825\r\n\r\nO", "K\r\n"]])
    let response = try channel.execute("AT+QNWINFO")
    #expect(response.lines == ["+QNWINFO: \"FDD LTE\",\"46011\",\"LTE BAND 3\",1825"])
    #expect(response.isOK)
}

@Test func reportsCMEError() throws {
    let (channel, _) = makeChannel(["AT+CIMI": ["\r\n+CME ERROR: 10\r\n"]])
    let response = try channel.execute("AT+CIMI")
    #expect(!response.isOK)
    #expect(response.errorMessage == "+CME ERROR: 10")
}

@Test func dropsEchoAndUnsolicitedCodes() throws {
    let (channel, _) = makeChannel([
        "AT+CSQ": ["AT+CSQ\r\n", "\r\n+CMTI: \"SM\",3\r\n", "\r\n+CSQ: 18,99\r\n\r\nOK\r\n"],
    ])
    let response = try channel.execute("AT+CSQ")
    #expect(response.lines == ["+CSQ: 18,99"])
}

@Test func keepsOwnResultEvenIfItLooksUnsolicited() throws {
    let (channel, _) = makeChannel(["AT+CEREG?": ["\r\n+CEREG: 2,1,\"5A0B\",\"8C3E21F\",7\r\n\r\nOK\r\n"]])
    let response = try channel.execute("AT+CEREG?")
    #expect(response.lines == ["+CEREG: 2,1,\"5A0B\",\"8C3E21F\",7"])
}

@Test func discardsStaleBytesOnOpen() throws {
    let (channel, transport) = makeChannel(["AT+CSQ": ["\r\n+CSQ: 9,99\r\n\r\nOK\r\n"]])
    // A late reply left behind by the previous user of the interface.
    transport.inject("\r\nEC25\r\n\r\nOK\r\n")
    try channel.open()
    let response = try channel.execute("AT+CSQ")
    #expect(response.lines == ["+CSQ: 9,99"])
}

@Test func unsolicitedCodeBetweenCommandsIsFiltered() throws {
    let (channel, transport) = makeChannel(["AT+CSQ": ["\r\n+CSQ: 9,99\r\n\r\nOK\r\n"]])
    try channel.open()
    // No drain on a healthy line: the code is read as part of the next reply and dropped.
    transport.inject("\r\n+QIND: SMS DONE\r\n")
    #expect(try channel.execute("AT+CSQ").lines == ["+CSQ: 9,99"])
}

@Test func dropsForeignPlusLinesButKeepsBareValues() throws {
    let (channel, _) = makeChannel([
        "AT+CSQ": ["\r\n+QSIMSTAT: 1,1\r\n+CSQ: 9,99\r\n\r\nOK\r\n"],
        "AT+GSN": ["\r\n+QUNKNOWN: x\r\n863000000000252\r\n\r\nOK\r\n"],
        "ATI": ["\r\nRDY\r\nQDC507\r\n\r\nOK\r\n"],
    ])
    #expect(try channel.execute("AT+CSQ").lines == ["+CSQ: 9,99"])
    #expect(try channel.execute("AT+GSN").lines == ["863000000000252"])
    #expect(try channel.execute("ATI").lines == ["QDC507"])
}

@Test func readErrorWithDeviceGoneIsDeviceNotFound() throws {
    let (channel, transport) = makeChannel(["AT+CSQ": []])
    try channel.open()
    transport.isDevicePresent = false
    transport.readError = ATTransportError.readFailed("no device")
    #expect(throws: ATError.deviceNotFound) { try channel.execute("AT+CSQ", timeout: 2) }
    #expect(!transport.isOpen)
}

@Test func readErrorWithDevicePresentIsNotConnected() throws {
    let (channel, transport) = makeChannel(["AT+CSQ": []])
    try channel.open()
    transport.readError = ATTransportError.readFailed("stall")
    let error = #expect(throws: ATError.self) { try channel.execute("AT+CSQ", timeout: 2) }
    guard case .notConnected? = error else {
        Issue.record("expected .notConnected, got \(String(describing: error))")
        return
    }
}

@Test func shutdownStopsAndPreventsReopen() throws {
    let (channel, transport) = makeChannel(["AT+CSQ": ["\r\n+CSQ: 9,99\r\n\r\nOK\r\n"]])
    try channel.open()
    channel.shutdown()
    #expect(!transport.isOpen)
    #expect(throws: ATError.self) { try channel.execute("AT+CSQ") }
    #expect(transport.openCount == 1)
}

@Test func timesOutWithoutFinalResult() {
    let (channel, _) = makeChannel(["AT+CSQ": ["\r\n+CSQ: 9,99\r\n"]])
    #expect(throws: ATError.timeout(command: "AT+CSQ")) {
        try channel.execute("AT+CSQ", timeout: 0.1)
    }
}

@Test func resyncsAfterTimeout() throws {
    let (channel, transport) = makeChannel([
        "AT+CSQ": [],
        "AT+CMEE?": ["\r\n+CMEE: 1\r\n\r\nOK\r\n"],
        "AT+QTEMP": ["\r\n+QTEMP: 50,45,45\r\n\r\nOK\r\n"],
    ])
    #expect(throws: ATError.timeout(command: "AT+CSQ")) { try channel.execute("AT+CSQ", timeout: 0.05) }
    // The late "ERROR" for AT+CSQ shows up before the next command.
    transport.inject("\r\nERROR\r\n")
    let response = try channel.execute("AT+QTEMP")
    #expect(response.isOK)
    #expect(response.lines == ["+QTEMP: 50,45,45"])
    #expect(transport.written.suffix(2) == ["AT+CMEE?", "AT+QTEMP"])
}

@Test func resyncIsNotFooledByALateOK() throws {
    let (channel, transport) = makeChannel([
        "AT+QENG=\"servingcell\"": [],
        "AT+CSQ": ["\r\n+CSQ: 23,99\r\n\r\nOK\r\n"],
        "AT+QTEMP": ["\r\n+QTEMP: 50,45,45\r\n\r\nOK\r\n"],
    ])
    #expect(throws: ATError.timeout(command: "AT+QENG=\"servingcell\"")) {
        try channel.execute("AT+QENG=\"servingcell\"", timeout: 0.05)
    }
    // The late reply of AT+QENG arrives first, the probe's own reply only after it.
    transport.inject("\r\n+QENG: \"servingcell\",\"NOCONN\"\r\n\r\nOK\r\n")
    transport.replies["AT+CMEE?"] = ["\r\n+CMEE: 1\r\n", "\r\nOK\r\n"]
    #expect(try channel.execute("AT+CSQ").lines == ["+CSQ: 23,99"])
    #expect(try channel.execute("AT+QTEMP").lines == ["+QTEMP: 50,45,45"])
}

@Test func failedResyncSkipsTheCommand() {
    let (channel, transport) = makeChannel(["AT+CSQ": [], "AT+CMEE?": []])
    #expect(throws: ATError.timeout(command: "AT+CSQ")) { try channel.execute("AT+CSQ", timeout: 0.05) }
    #expect(throws: ATError.timeout(command: "AT+QTEMP")) { try channel.execute("AT+QTEMP") }
    #expect(!transport.written.contains("AT+QTEMP"))
}

@Test func suspendedChannelReportsBusyUntilResumed() throws {
    let (channel, transport) = makeChannel(["AT+CSQ": ["\r\n+CSQ: 9,99\r\n\r\nOK\r\n"]])
    try channel.open()
    channel.suspend()
    #expect(throws: ATError.busy) { try channel.execute("AT+CSQ") }
    channel.resume()
    #expect(try channel.execute("AT+CSQ").isOK)
    #expect(transport.isOpen)
}

@Test func openFailuresAreClassified() {
    let (channel, transport) = makeChannel()
    transport.openError = ATTransportError.busy
    #expect(throws: ATError.busy) { try channel.execute("AT") }
    transport.openError = ATTransportError.deviceNotFound
    #expect(throws: ATError.deviceNotFound) { try channel.execute("AT") }
    transport.openError = ATTransportError.openFailed("x")
    // The message is localized; only the kind matters here.
    let error = #expect(throws: ATError.self) { try channel.execute("AT") }
    if case let .notConnected(message)? = error {
        #expect(message.hasSuffix("x"))
    } else {
        Issue.record("expected .notConnected, got \(String(describing: error))")
    }
}

@Test func resultPrefix() {
    #expect(ATChannel.resultPrefix(of: "AT+CSQ") == "+CSQ")
    #expect(ATChannel.resultPrefix(of: "AT+CEREG?") == "+CEREG")
    #expect(ATChannel.resultPrefix(of: "AT+QENG=\"servingcell\"") == "+QENG")
    #expect(ATChannel.resultPrefix(of: "ATI") == nil)
}
