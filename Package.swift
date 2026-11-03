// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LTE Modem Stats",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "lte-modem-stats", targets: ["lte-modem-stats"]),
    ],
    targets: [
        .target(
            name: "CUSBAT",
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("IOUSBHost"),
            ]
        ),
        .target(
            name: "ModemCore",
            dependencies: ["CUSBAT"]
        ),
        .executableTarget(
            name: "lte-modem-stats",
            dependencies: ["ModemCore"]
        ),
        .testTarget(
            name: "ModemCoreTests",
            dependencies: ["ModemCore"],
            // Read through #filePath, not bundled.
            exclude: ["Fixtures"]
        ),
    ]
)
