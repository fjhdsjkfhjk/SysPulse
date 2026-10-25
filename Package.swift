// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SysPulse",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SysPulse",
            path: "Sources/SysPulse",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("CoreWLAN"),
            ]
        )
    ]
)
