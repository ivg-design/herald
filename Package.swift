// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Herald",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HeraldClient", targets: ["HeraldClient"]),
        .executable(name: "herald", targets: ["herald"]),
        .executable(name: "herald-mcp", targets: ["herald-mcp"]),
    ],
    dependencies: [
        // The Rive Apple runtime (a binary xcframework, macOS 13.1+) for the banner `rive` component. Only the
        // Xcode app target (Herald.app, see project.yml) links it; HeraldClient and HeraldCore stay dependency-free,
        // so no target below lists it. It is declared here so one version is pinned for the whole repo.
        .package(url: "https://github.com/rive-app/rive-ios", exact: "6.28.0"),
    ],
    targets: [
        .target(name: "HeraldClient", path: "Sources/HeraldClient"),
        .executableTarget(name: "herald", dependencies: ["HeraldClient"], path: "Sources/herald-cli"),
        // The MCP server (stdio JSON-RPC) that lets an agent author templates; talks to Herald over its HTTP API.
        .executableTarget(name: "herald-mcp", dependencies: ["HeraldClient"], path: "Sources/herald-mcp"),
        // The pure (AppKit-free) part of the app, compiled here so the router, history store and
        // snooze math can be unit tested. The Xcode app target compiles Sources/Herald directly.
        .target(name: "HeraldCore", dependencies: ["HeraldClient"],
                path: "Sources/Herald", exclude: ["Help/HeraldHelp.swift"], sources: ["Core", "Help", "Authoring/CodeExport.swift", "Authoring/ComposerModel.swift",
                         "Designer/DesignerModel.swift", "Designer/SymbolBrowser.swift", "Voice/TTSWorker.swift", "Voice/KokoroInstaller.swift", "Voice/SpeechQueue.swift", "Voice/AudioCache.swift", "Voice/KokoroLayout.swift", "Voice/QuietHours.swift", "MCP/MCPInstaller.swift", "MCP/AgentIdentity.swift", "MCP/AgentIssuer.swift", "MCP/AgentIconSources.swift",
                         "Relay/RelaySwitch.swift", "Relay/RelaySetup.swift", "Relay/RelayCloudConfig.swift", "Relay/CloudflareDeployer.swift", "Relay/RelayInstructions.swift", "Relay/RelayModels.swift", "Relay/RelayStore.swift", "Relay/SecretVault.swift", "Relay/RelayAPI.swift", "Relay/RelayPolicy.swift", "Relay/RelayClient.swift", "Relay/VoiceReply.swift", "Relay/RelayRoutes.swift", "Relay/CloudApps.swift"]),
        .testTarget(name: "HeraldTests", dependencies: ["HeraldClient", "HeraldCore", "herald-mcp"],
                    path: "Tests/HeraldTests"),
    ]
)
