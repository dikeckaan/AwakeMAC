// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LidAwake",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LidAwake",
            path: "Sources/LidAwake",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
