import Foundation
import HeraldClient

/// Checks an agent-written template document can only be done on the raw JSON: Codable ignores a key it does
/// not know, so `"colspan": 2` silently becomes `colSpan: 1`. This finds such keys (compared with the keys the
/// component schema lists) and offers the closest real name.
enum TemplateKeyCheck {
    /// Keys the template decoder reads that the schema's top-level `properties` does not list (the v1 look).
    private static let legacyTemplateKeys: Set<String> = [
        "layout", "showSubtitle", "showBody", "showTimestamp", "maxBodyLines", "image", "url", "priority", "reminder",
    ]

    private static let schema = ComponentSchema.document()

    private static func keys(at path: [String]) -> Set<String> {
        var v: JSONValue? = schema
        for p in path { v = v?[p] }
        return Set(v?.objectValue?.keys.map { $0 } ?? [])
    }

    private static let templateKeys = keys(at: ["properties"]).union(legacyTemplateKeys)
    private static let gridKeys = keys(at: ["definitions", "grid", "properties"])
    private static let cellKeys = keys(at: ["definitions", "cell", "properties"])
    private static let actionKeys = keys(at: ["definitions", "action", "properties"])
    private static let ruleKeys = keys(at: ["definitions", "actionRule", "properties"])
    private static func componentKeys(_ type: String) -> Set<String> {
        keys(at: ["components", type, "properties"]).union(["type"])
    }

    /// Warnings for every key of `raw` that the format does not know.
    static func warnings(in raw: [String: JSONValue]) -> [HeraldTemplateIssue] {
        var out: [HeraldTemplateIssue] = []

        func check(_ obj: [String: JSONValue], known: Set<String>, path: String, cell: String?) {
            guard !known.isEmpty else { return }
            for key in obj.keys.sorted() where !known.contains(key) {
                var msg = "unknown key '\(key)' is ignored"
                if let near = closest(to: key, in: known) { msg += " (did you mean '\(near)'?)" }
                out.append(.init(severity: .warning, path: path.isEmpty ? key : "\(path).\(key)", cellId: cell, message: msg))
            }
        }
        func checkAction(_ v: JSONValue?, path: String, cell: String?) {
            if case .object(let a)? = v { check(a, known: actionKeys, path: path, cell: cell) }
        }

        check(raw, known: templateKeys, path: "", cell: nil)
        if case .object(let g)? = raw["grid"] { check(g, known: gridKeys, path: "grid", cell: nil) }
        for (i, rule) in (raw["actionRules"]?.arrayValue ?? []).enumerated() {
            guard case .object(let r) = rule else { continue }
            check(r, known: ruleKeys, path: "actionRules[\(i)]", cell: nil)
            checkAction(r["add"], path: "actionRules[\(i)].add", cell: nil)
        }
        for (i, cellValue) in (raw["cells"]?.arrayValue ?? []).enumerated() {
            guard case .object(let c) = cellValue else { continue }
            let id = c["id"]?.stringValue
            check(c, known: cellKeys, path: "cells[\(i)]", cell: id)
            if case .object(let comp)? = c["component"], case .string(let type)? = comp["type"] {
                check(comp, known: componentKeys(type), path: "cells[\(i)].component", cell: id)
                checkAction(comp["action"], path: "cells[\(i)].component.action", cell: id)
            }
        }
        return out
    }

    /// The known name closest to `key` (case-insensitive match, or an edit distance of at most 2).
    static func closest(to key: String, in known: Set<String>) -> String? {
        let lower = key.lowercased()
        if let exact = known.first(where: { $0.lowercased() == lower }) { return exact }
        var best: (String, Int)?
        for k in known.sorted() {
            let d = editDistance(lower, k.lowercased())
            if d <= 2, best == nil || d < best!.1 { best = (k, d) }
        }
        return best?.0
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
