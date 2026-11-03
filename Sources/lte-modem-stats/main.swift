import Foundation
import ModemCore

// No argument: menu bar app. Otherwise a CLI subcommand (see CLI/Commands.swift).
L10n.apply(AppSettings.storedLanguage())

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "status":
    exit(runStatus(json: arguments.contains("--json")))
case "traffic":
    exit(runTraffic(watch: arguments.contains("--watch")))
case "at":
    exit(runAT(Array(arguments.dropFirst())))
case nil:
    MainActor.assumeIsolated { MenuBarApp.run() }
case "-v", "--version", "version":
    print("LTE Modem Stats \(AppVersion.display)")
case "-h", "--help", "help":
    print(usage())
default:
    printError(usage())
    exit(2)
}
