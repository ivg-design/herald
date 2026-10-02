import Foundation

/// Where an agent's real icon can be found on this Mac (issue #62): the product's application bundle, else the
/// command line package or data folder it ships in. Claude Code and Claude Desktop share Claude.app's icon.
public enum AgentIconSources {
    public struct Roots: Sendable {
        /// Folders holding applications.
        public var applications: [URL]
        /// Global npm `node_modules` folders (`npm root -g` and the usual places).
        public var npmRoots: [URL]
        /// Folders the `claude` command keeps its files in.
        public var claudeData: [URL]

        public init(applications: [URL], npmRoots: [URL], claudeData: [URL]) {
            self.applications = applications; self.npmRoots = npmRoots; self.claudeData = claudeData
        }

        public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Roots {
            Roots(applications: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")],
                  npmRoots: [URL(fileURLWithPath: "/opt/homebrew/lib/node_modules"), URL(fileURLWithPath: "/usr/local/lib/node_modules"),
                             home.appendingPathComponent(".npm-global/lib/node_modules")],
                  claudeData: [home.appendingPathComponent(".local/share/claude"), home.appendingPathComponent(".claude/local")])
        }
    }

    /// The application bundles that carry this agent's icon, best first.
    public static func appBundles(for kind: AgentIdentity.Kind, in roots: Roots) -> [URL] {
        let names: [String]
        switch kind {
        case .claudeCode, .claudeDesktop: names = ["Claude.app"]
        case .codex: names = ["Codex.app", "OpenAI Codex.app"]
        case .generic: names = []
        }
        return roots.applications.flatMap { folder in names.map { folder.appendingPathComponent($0) } }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Folders of the command line package, searched when the app is absent.
    public static func packageFolders(for kind: AgentIdentity.Kind, in roots: Roots) -> [URL] {
        switch kind {
        case .claudeCode, .claudeDesktop:
            return roots.npmRoots.map { $0.appendingPathComponent("@anthropic-ai/claude-code") } + roots.claudeData
        case .codex:
            return roots.npmRoots.map { $0.appendingPathComponent("@openai/codex") }
        case .generic:
            return []
        }
    }

    /// The best icon-looking `.icns` or `.png` under `folder` (a name with icon, logo or app in it; the largest file wins).
    public static func iconFile(in folder: URL, maxDepth: Int = 4) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path),
              let walker = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        var best: (url: URL, size: Int)?
        for case let url as URL in walker {
            if walker.level > maxDepth { walker.skipDescendants(); continue }
            let ext = url.pathExtension.lowercased()
            guard ext == "icns" || ext == "png" else { continue }
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            guard ["icon", "logo", "app"].contains(where: name.contains) else { continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let size = values?.fileSize, size > 0 else { continue }
            if best == nil || size > best!.size { best = (url, size) }
        }
        return best?.url
    }

    /// The icon as PNG and where it came from, or nil when this Mac has none.
    public static func png(for kind: AgentIdentity.Kind, roots: Roots = .standard(),
                           convert: (URL) -> Data? = { IconExtractor.png(from: $0) }) -> (data: Data, source: URL)? {
        for bundle in appBundles(for: kind, in: roots) {
            if let icns = IconExtractor.icnsURL(inBundle: bundle), let png = convert(icns) { return (png, bundle) }
        }
        for folder in packageFolders(for: kind, in: roots) {
            if let file = iconFile(in: folder), let png = convert(file) { return (png, file) }
        }
        return nil
    }
}
