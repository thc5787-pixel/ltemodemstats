import Foundation
import ModemCore

/// Subcommands: `status`, `traffic`, `at`. Each returns the process exit code.

func usage() -> String {
    L10n.t("""
    用法：
      lte-modem-stats                            常驻菜单栏（无 Dock 图标）
      lte-modem-stats status [--json]            读取并打印模块完整状态
      lte-modem-stats traffic [--watch]          显示模块网卡流量（--watch 每秒刷新网速）
      lte-modem-stats at <AT 指令> [更多指令 …]   向模块发送 AT 指令并打印回复
                                                 例：lte-modem-stats at AT+CSQ 'AT+QENG="servingcell"'
      lte-modem-stats --version                  显示版本号
    """, """
    Usage:
      lte-modem-stats                            Run in the menu bar (no Dock icon)
      lte-modem-stats status [--json]            Read and print the full modem status
      lte-modem-stats traffic [--watch]          Show traffic of the modem's interface (--watch: rate every second)
      lte-modem-stats at <command> [more …]      Send AT commands and print the replies
                                                 e.g. lte-modem-stats at AT+CSQ 'AT+QENG="servingcell"'
      lte-modem-stats --version                  Show the version
    """)
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Opens the AT interface, borrowing it from the menu bar app if that holds it.
/// The returned closure releases it (and hands it back to the app).
func openChannel() throws -> (ATChannel, release: () -> Void) {
    let channel = ATChannel()
    let borrowed = try ATHandoff.open(channel)
    return (channel, {
        channel.close()
        if borrowed { ATHandoff.finish() }
    })
}

func runAT(_ commands: [String]) -> Int32 {
    guard !commands.isEmpty else {
        printError(usage())
        return 2
    }
    let channel: ATChannel
    let release: () -> Void
    do {
        (channel, release) = try openChannel()
    } catch {
        printError(error.localizedDescription)
        return 1
    }
    defer { release() }

    var status: Int32 = 0
    for command in commands {
        print("> \(command)")
        do {
            let response = try channel.execute(command)
            response.lines.forEach { print($0) }
            if response.isOK {
                print("OK")
            } else {
                print(response.errorMessage ?? "ERROR")
                status = 1
            }
        } catch {
            printError(error.localizedDescription)
            status = 1
        }
    }
    return status
}

func runStatus(json: Bool) -> Int32 {
    do {
        let (channel, release) = try openChannel()
        defer { release() }
        let (status, timedOut) = try ModemReader(channel: channel).readAll()
        if !timedOut.isEmpty {
            printError(L10n.t("部分信息读取超时：", "Some reads timed out: ")
                + timedOut.map { "\($0)" }.sorted().joined(separator: ", "))
        }
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(status), as: UTF8.self))
        } else {
            print(StatusText.render(status))
        }
        return 0
    } catch {
        printError(error.localizedDescription)
        return 1
    }
}

func runTraffic(watch: Bool) -> Int32 {
    guard let name = NetworkInterfaces.modemInterface() else {
        printError(L10n.t("未找到模块网卡（2c7c:0125 下没有 en* 接口）。", "Modem network interface not found (no en* interface under 2c7c:0125)."))
        return 1
    }
    // Read-only view of the history; only the menu bar process writes it.
    var meter = TrafficMeter(history: TrafficHistory.load(from: TrafficHistory.defaultURL))
    meter.record(NetworkInterfaces.counters(for: name), at: Date())
    guard let session = meter.session else {
        printError(L10n.t("无法读取 \(name) 的流量计数。", "Cannot read traffic counters of \(name)."))
        return 1
    }
    print(L10n.t("网卡      ", "Interface ") + name)
    print(L10n.t("本次连接  ", "Session   ") + "↓ \(ByteFormat.bytes(session.rx))  ↑ \(ByteFormat.bytes(session.tx))")
    let today = meter.today()
    let billingDay = AppSettings.storedBillingDay()
    let cycle = meter.cycle(startDay: billingDay)
    print(L10n.t("今日      ", "Today     ") + "↓ \(ByteFormat.bytes(today.rx))  ↑ \(ByteFormat.bytes(today.tx))"
        + L10n.t("（菜单栏程序运行期间统计）", " (counted while the menu bar app runs)"))
    print(L10n.t("本月      ", "This cycle ") + ByteFormat.bytes(cycle.total) + L10n.t("（每月 \(billingDay) 日起算）", " (resets on day \(billingDay))"))

    repeat {
        Thread.sleep(forTimeInterval: 1)
        meter.record(NetworkInterfaces.counters(for: name), at: Date())
        print(L10n.t("网速      ", "Rate      ") + "↓ \(ByteFormat.rate(meter.rxRate))  ↑ \(ByteFormat.rate(meter.txRate))")
        fflush(stdout)
    } while watch
    return 0
}
