// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AwakeMac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AwakeMac",
            path: "Sources/AwakeMac",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
