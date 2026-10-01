import Foundation
import HeraldClient

/// The MCP resources: manifests, templates and the components guide, as documents an agent can read.
///
///     herald://manifests/<app>
///     herald://templates/<app>/<name>
///     herald://docs/components
final class MCPResources: @unchecked Sendable {
    static let scheme = "herald://"
    static let componentsURI = "herald://docs/components"

    let client: HeraldClient
    private let describe: (Error) -> String

    init(client: HeraldClient, describe: @escaping (Error) -> String) {
        self.client = client
        self.describe = describe
    }

    /// `herald://manifests/webwatcher.email`; path components are percent-encoded (a template named "Bid won" is `Bid%20won`).
    static func uri(manifest app: String) -> String { scheme + "manifests/" + encode(app) }
    static func uri(template name: String, app: String) -> String { scheme + "templates/" + encode(app) + "/" + encode(name) }

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? s
    }

    /// The URI templates (`resources/templates/list`).
    static let uriTemplates: [JSONValue] = [
        .object(["uriTemplate": .string("herald://manifests/{app}"), "name": .string("manifest"),
                 "title": .string("App manifest"),
                 "description": .string("The fields and actions an app declares, with sample values."),
                 "mimeType": .string("application/json")]),
        .object(["uriTemplate": .string("herald://templates/{app}/{name}"), "name": .string("template"),
                 "title": .string("Banner template"),
                 "description": .string("A template's JSON (name may also be builtin.imageLeft, builtin.imageRight, builtin.hero, builtin.compact)."),
                 "mimeType": .string("application/json")]),
    ]

    /// Everything that can be read right now. The components guide is always there; manifests and templates only
    /// when Herald answers.
    func list() async -> [JSONValue] {
        var out: [JSONValue] = [
            .object(["uri": .string(Self.componentsURI), "name": .string("components"), "title": .string("Template components guide"),
                     "description": .string("How a banner template is built: grid, components, bindings, empty-collapsing, actions. Read before authoring; component_schema has every property."),
                     "mimeType": .string("text/markdown")]),
        ]
        for m in (try? await client.manifests()) ?? [] {
            out.append(.object(["uri": .string(Self.uri(manifest: m.app)), "name": .string("manifest: \(m.app)"),
                                "title": .string("\(m.appName) manifest"),
                                "description": .string("\(m.fields.count) fields, \(m.actions.count) actions"),
                                "mimeType": .string("application/json")]))
        }
        for t in (try? await client.templates()) ?? [] {
            out.append(.object(["uri": .string(Self.uri(template: t.name, app: t.app)), "name": .string("template: \(t.app)/\(t.name)"),
                                "title": .string("\(t.app): \(t.name)"),
                                "description": .string(t.usesGrid ? "grid template, \(t.cells.count) cells" : "v1 template (\(t.layout.rawValue))"),
                                "mimeType": .string("application/json")]))
        }
        return out
    }

    /// The `resources/read` result.
    func read(uri: String) async throws -> JSONValue {
        guard uri.hasPrefix(Self.scheme) else { throw RPCError.resourceNotFound(uri) }
        let parts = uri.dropFirst(Self.scheme.count).split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).removingPercentEncoding ?? String($0) }

        func contents(_ text: String, mime: String) -> JSONValue {
            .object(["contents": .array([.object(["uri": .string(uri), "mimeType": .string(mime), "text": .string(text)])])])
        }

        switch parts.first ?? "" {
        case "docs" where parts == ["docs", "components"]:
            return contents(ComponentSchema.guide(), mime: "text/markdown")
        case "manifests" where parts.count == 2 && !parts[1].isEmpty:
            let manifest: HeraldManifest?
            do { manifest = try await client.manifest(app: parts[1]) } catch { throw RPCError.internalError(describe(error)) }
            guard let m = manifest else { throw RPCError.resourceNotFound(uri) }
            return contents(try JSONValue(encoding: m).abbreviated().text(), mime: "application/json")
        case "templates" where parts.count == 3 && !parts[1].isEmpty && !parts[2].isEmpty:
            let template: HeraldTemplate?
            do { template = try await client.template(app: parts[1], name: parts[2]) } catch { throw RPCError.internalError(describe(error)) }
            guard let t = template else { throw RPCError.resourceNotFound(uri) }
            return contents(try JSONValue(encoding: t).text(), mime: "application/json")
        default:
            throw RPCError.resourceNotFound(uri)
        }
    }
}
