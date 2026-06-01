// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CCUsageWidget",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cc-usage-widget", targets: ["CCUsageWidget"])
    ],
    targets: [
        .executableTarget(
            name: "CCUsageWidget",
            resources: [
                .copy("Resources/logo.ico")
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)