import Foundation
@testable import ModemCore
import Testing

private func connectedStatus(rsrp: Int = -83, sim: SIMInfo.State = .ready,
                             registration: Registration = .home) -> ModemStatus {
    var status = ModemStatus()
    status.sim = SIMInfo(state: sim)
    status.network = NetworkInfo(operatorName: "CHN-CT", generation: .lte, registration: registration,
                                 band: "LTE BAND 3")
    status.signal = SignalInfo(rsrp: rsrp)
    return status
}

/// Presentation texts depend on the global language: run these one at a time with a fixed language.
@Suite(.serialized) struct PresentationTests {
    init() { L10n.apply(.chinese) }

    @Test func connectedShowsBarsAndGeneration() {
        let presentation = MenuBarPresentation(connection: .connected, status: connectedStatus(rsrp: -100),
                                               rates: (1_258_291, 81920), showRates: true, quotaFraction: nil)
        #expect(presentation.active)
        #expect(presentation.bars == 2)
        #expect(presentation.label == "4G")
        #expect(presentation.rates == "↓1.2M ↑\u{2007}80K")
        #expect(presentation.tint == .none)
        #expect(presentation.tooltip == "LTE Modem Stats\nCHN-CT · LTE BAND 3")
    }

    @Test func ratesCanBeHidden() {
        let presentation = MenuBarPresentation(connection: .connected, status: connectedStatus(),
                                               rates: (1, 1), showRates: false, quotaFraction: nil)
        #expect(presentation.rates == nil)
    }

    @Test func problemStatesDimTheBars() {
        let cases: [(ModemService.Connection, ModemStatus, String)] = [
            (.notFound, ModemStatus(), "无设备"),
            (.busy, ModemStatus(), "占用"),
            (.failed("模块无响应"), ModemStatus(), "!"),
            (.connected, connectedStatus(sim: .notInserted), "无卡"),
            (.connected, connectedStatus(sim: .pinRequired), "SIM"),
            (.connected, connectedStatus(registration: .searching), "无服务"),
        ]
        for (connection, status, label) in cases {
            let presentation = MenuBarPresentation(connection: connection, status: status,
                                                   rates: nil, showRates: true, quotaFraction: nil)
            #expect(presentation.label == label)
            #expect(!presentation.active)
            #expect(presentation.bars == 0)
        }
    }

    @Test func busyStillShowsTraffic() {
        let presentation = MenuBarPresentation(connection: .busy, status: ModemStatus(),
                                               rates: (2048, 0), showRates: true, quotaFraction: nil)
        #expect(presentation.rates == "↓2.0K ↑\u{2007}\u{2007}0B")
    }

    @Test func quotaTints() {
        func tint(_ fraction: Double?) -> MenuBarPresentation.Tint {
            MenuBarPresentation(connection: .connected, status: connectedStatus(),
                                rates: nil, showRates: true, quotaFraction: fraction).tint
        }
        #expect(tint(nil) == .none)
        #expect(tint(0.79) == .none)
        #expect(tint(0.8) == .warning)
        #expect(tint(1.2) == .critical)
    }

    @Test func englishLabels() {
        L10n.apply(.english)
        defer { L10n.apply(.chinese) }
        let notFound = MenuBarPresentation(connection: .notFound, status: ModemStatus(),
                                           rates: nil, showRates: true, quotaFraction: nil)
        #expect(notFound.label == "No modem")
        #expect(notFound.tooltip == "LTE Modem Stats\nModem not found")
        let noService = MenuBarPresentation(connection: .connected, status: connectedStatus(registration: .searching),
                                            rates: nil, showRates: true, quotaFraction: nil)
        #expect(noService.label == "No service")
        #expect(ATError.busy.errorDescription == "The modem's AT interface is in use by another program.")
        #expect(RadioGeneration.none.displayName == "No service")
        #expect(RadioGeneration.lte.displayName == "4G")
    }

    @Test func unresponsiveShowsWarning() {
        let presentation = MenuBarPresentation(connection: .unresponsive, status: ModemStatus(),
                                               rates: nil, showRates: true, quotaFraction: nil)
        #expect(presentation.label == "!")
        #expect(presentation.tooltip == "LTE Modem Stats\n模块无响应")
    }
}

// MARK: - Language

@Test func systemLanguageFollowsPreferredLanguages() {
    #expect(L10n.resolve(.system, preferred: ["zh-Hans-CN", "en-US"]) == .chinese)
    #expect(L10n.resolve(.system, preferred: ["zh-Hant-TW"]) == .chinese)
    #expect(L10n.resolve(.system, preferred: ["en-US", "zh-Hans"]) == .english)
    #expect(L10n.resolve(.system, preferred: []) == .english)
    #expect(L10n.resolve(.chinese, preferred: ["en-US"]) == .chinese)
    #expect(L10n.resolve(.english, preferred: ["zh-Hans"]) == .english)
}
