import Foundation

/// The one rule for the name of a template a user, an agent or a bundle creates or renames. The API (PUT, duplicate,
/// rename), the MCP server, the Designer and the bundle import all ask it. Names that are already stored and break the
/// rule (older, longer, or `builtin.`-prefixed) still load, list, delete and rename: only new names are checked.
public enum HeraldTemplateName {
    /// Longest name, in UTF-8 bytes (the name is also a file name).
    public static let maxBytes = 128
    /// Names starting with this belong to the built-in layouts.
    public static var reservedPrefix: String { BuiltinTemplates.prefix }

    /// Why `name` cannot be used for a new or renamed template; nil when it can. Whitespace is not trimmed here.
    /// `allowScratch` lets a leading `_` through: scratch templates (the Designer's `_designer-test`) are written by
    /// name and never listed, and PUT /v1/templates has always accepted them.
    public static func problem(_ name: String, allowScratch: Bool = false) -> String? {
        if name.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty { return "the name is empty" }
        if name.contains("/") || name.contains(":") { return "the name cannot contain / or :" }
        if name.hasPrefix(".") || (!allowScratch && name.hasPrefix("_")) { return "the name cannot start with . or _ (those are reserved)" }
        if name.hasPrefix(reservedPrefix) { return "names starting with \(reservedPrefix) are reserved for the built-in layouts" }
        if name.utf8.count > maxBytes { return "the name is longer than \(maxBytes) bytes" }
        return nil
    }

    /// `name` cut to `maxBytes` UTF-8 bytes at a character boundary.
    public static func truncated(_ name: String) -> String {
        var out = "", bytes = 0
        for ch in name {
            let n = String(ch).utf8.count
            if bytes + n > maxBytes { break }
            out.append(ch); bytes += n
        }
        return out
    }
}

/// The one rule for the name of a script action: a plain file name in Application Support/Herald/scripts. Template
/// validation and the action runner both ask it, so a name that validates always resolves the same way.
public enum HeraldScriptName {
    /// True for a file name with no path separator, no `.`/`..`, no leading `~` and no control characters.
    public static func isPlain(_ raw: String) -> Bool {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != ".", n != "..", !n.hasPrefix("~"),
              !n.contains("/"), !n.contains("\\"), !n.contains("\0"),
              !n.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        return true
    }
}
