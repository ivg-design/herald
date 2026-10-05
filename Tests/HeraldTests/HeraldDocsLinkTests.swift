import XCTest
import Foundation
@testable import HeraldClient
@testable import HeraldCore

/// Every docs page the app links to must exist on the site: the route is /docs/<group>/<slug> (web/src/lib/docs-tree.ts),
/// published under the /apps/herald prefix, so `HeraldDocs.baseURL + "/<group>/<slug>"`.
final class HeraldDocsLinkTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// "group/slug" for every page in DOC_TREE, parsed from the TypeScript source (groups are `id:` lines, pages `slug:` lines).
    private func siteRoutes() throws -> Set<String> {
        let src = try String(contentsOf: repoRoot.appendingPathComponent("web/src/lib/docs-tree.ts"), encoding: .utf8)
        var routes = Set<String>()
        var group: String?
        let groupRx = try NSRegularExpression(pattern: #"^\s*id:\s*"([^"]+)""#)
        let slugRx = try NSRegularExpression(pattern: #"\{\s*slug:\s*"([^"]+)""#)
        for line in src.split(separator: "\n").map(String.init) {
            let r = NSRange(line.startIndex..., in: line)
            if let m = groupRx.firstMatch(in: line, range: r), let g = Range(m.range(at: 1), in: line) { group = String(line[g]) }
            else if let m = slugRx.firstMatch(in: line, range: r), let s = Range(m.range(at: 1), in: line), let g = group {
                routes.insert("\(g)/\(line[s])")
            }
        }
        return routes
    }

    /// Every page path written in Sources: `docsPage` returns and `HeraldDocs.baseURL)/<page>` literals.
    private func pagesInSources() throws -> Set<String> {
        var pages = Set<String>()
        let rx = try NSRegularExpression(pattern: #"(?:baseURL\)/|return\s+")((?:[a-z0-9-]+)/(?:[a-z0-9-]+))(?=[\s"\\)])"#)
        let en = FileManager.default.enumerator(at: repoRoot.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)
        while let u = en?.nextObject() as? URL {
            guard u.pathExtension == "swift" else { continue }
            let s = try String(contentsOf: u, encoding: .utf8)
            for m in rx.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                if let r = Range(m.range(at: 1), in: s) { pages.insert(String(s[r])) }
            }
        }
        return pages
    }

    func testBaseURLMatchesTheSiteRoute() {
        XCTAssertEqual(HeraldDocs.baseURL, "https://forge.mograph.life/apps/herald/docs")
        XCTAssertEqual(HeraldDocs.url("cloud/device-flow")?.absoluteString, "https://forge.mograph.life/apps/herald/docs/cloud/device-flow")
    }

    func testTheRouteListIsParsed() throws {
        let routes = try siteRoutes()
        XCTAssertGreaterThan(routes.count, 20)
        XCTAssertTrue(routes.contains("cloud/connect-chatgpt"))
    }

    func testEveryAgentGuideIsAPageOnTheSite() throws {
        let routes = try siteRoutes()
        for agent in RelayInstructions.Agent.allCases {
            XCTAssertTrue(routes.contains(agent.docsPage), "\(agent) links to \(agent.docsPage), which is not a docs route")
        }
    }

    func testEveryDocsPageNamedInSourcesIsAPageOnTheSite() throws {
        let routes = try siteRoutes()
        let pages = try pagesInSources()
        XCTAssertTrue(pages.isSuperset(of: ["cloud/connect-chatgpt", "cloud/connect-agent", "cloud/device-flow", "cloud/reply-events"]), "scan found \(pages.sorted())")
        for p in pages { XCTAssertTrue(routes.contains(p), "Sources link to \(p), which is not a docs route") }
    }
}
