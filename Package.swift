// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InstantSpaceSwitcher",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "InstantSpaceSwitcher", targets: ["InstantSpaceSwitcher"])
    ],
    targets: [
        .target(
            name: "ISS",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "InstantSpaceSwitcher",
            dependencies: ["ISS"]
        ),
        .testTarget(
            name: "ISSTests",
            dependencies: ["ISS", "InstantSpaceSwitcher"]
        )
    ]
)
