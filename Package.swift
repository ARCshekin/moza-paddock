// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "moza-driver",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MozaKit", targets: ["MozaKit"]),
        .executable(name: "mozactl", targets: ["mozactl"]),
        .executable(name: "moza-ac-bridge", targets: ["MozaACBridge"]),
        .executable(name: "MozaControl", targets: ["MozaApp"]),
        .executable(name: "MozaPaddock", targets: ["Paddock"]),
    ],
    targets: [
        .target(name: "CBridgeAtomics"),
        .target(
            name: "MozaKit",
            dependencies: ["CBridgeAtomics"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("ForceFeedback"),
            ]
        ),
        .executableTarget(name: "Paddock", dependencies: ["MozaKit"], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI")]),
        .executableTarget(name: "MozaACBridge", dependencies: ["MozaKit"]),
        .testTarget(name: "MozaBridgeTests", dependencies: ["MozaKit"]),
        .executableTarget(name: "mozactl", dependencies: ["MozaKit"],
                          linkerSettings: [.linkedFramework("AppKit")]),
        .executableTarget(
            name: "MozaApp",
            dependencies: ["MozaKit"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI")]
        ),
    ]
)
