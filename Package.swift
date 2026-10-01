// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Herald",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HeraldClient", targets: ["HeraldClient"]),
        .executable(name: "herald", targets: ["herald"]),
    ],
    targets: [
        .target(name: "HeraldClient", path: "Sources/HeraldClient"),
        .executableTarget(name: "herald", dependencies: ["HeraldClient"], path: "Sources/herald-cli"),
        // The pure (AppKit-free) part of the app, compiled here so the router, history store and
        // snooze math can be unit tested. The Xcode app target compiles Sources/Herald directly.
        .target(name: "HeraldCore", dependencies: ["HeraldClient"],
                path: "Sources/Herald", sources: ["Core", "Authoring/CodeExport.swift", "Authoring/ComposerModel.swift"]),
        .testTarget(name: "HeraldTests", dependencies: ["HeraldClient", "HeraldCore"],
                    path: "Tests/HeraldTests"),
    ]
)
