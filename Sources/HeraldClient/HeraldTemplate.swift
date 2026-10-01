import Foundation

/// How a banner is arranged. One SwiftUI view renders all four (DESIGN section 6).
public enum HeraldLayout: String, Codable, CaseIterable, Sendable {
    /// Image thumbnail on the left, text on the right. The default.
    case imageLeft
    /// Same, mirrored.
    case imageRight
    /// Image across the top at 16:9, text underneath.
    case hero
    /// One line: app icon and title. No image.
    case compact
}

/// A reusable banner look plus default content, stored per app and referenced from a notification
/// as `"template": "<name>"`. Everything except `name` and `app` is optional on the wire, so a
/// hand-written file or a minimal PUT body decodes; `TemplateResolver` merges it with a payload.
public struct HeraldTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String { app + "/" + name }
    public var name: String
    public var app: String
    public var layout: HeraldLayout
    /// Hex colour such as `#34C759`; nil keeps the system accent.
    public var accentColor: String?
    public var showSubtitle: Bool
    public var showBody: Bool
    public var showTimestamp: Bool
    public var maxBodyLines: Int

    // Default content. `title`, `subtitle`, `body` and `url` may contain `{placeholder}` tokens.
    public var title: String?
    public var subtitle: String?
    public var body: String?
    public var image: String?
    public var url: String?
    /// Default button set, used when the payload sends no `buttons`.
    public var buttons: [HeraldButton]
    public var sound: String?
    public var persistent: Bool?
    public var timeout: Double?
    public var snooze: Bool?
    public var priority: String?
    public var reminder: HeraldReminder?

    /// Line limit the pre-template banner used, so an untemplated look and a bare template match.
    public static let defaultMaxBodyLines = 8

    public init(name: String, app: String, layout: HeraldLayout = .imageLeft) {
        self.name = name; self.app = app; self.layout = layout
        self.accentColor = nil
        self.showSubtitle = true; self.showBody = true; self.showTimestamp = true
        self.maxBodyLines = Self.defaultMaxBodyLines
        self.title = nil; self.subtitle = nil; self.body = nil; self.image = nil; self.url = nil
        self.buttons = []
        self.sound = nil; self.persistent = nil; self.timeout = nil; self.snooze = nil
        self.priority = nil; self.reminder = nil
    }

    // `id` is derived, so the coding keys list the stored properties only. Decoding is written out
    // (instead of synthesized) because synthesis would demand every non-optional key; here a
    // template like {"name":"n","app":"a"} must decode with the documented defaults.
    private enum CodingKeys: String, CodingKey {
        case name, app, layout, accentColor, showSubtitle, showBody, showTimestamp, maxBodyLines
        case title, subtitle, body, image, url, buttons, sound, persistent, timeout, snooze
        case priority, reminder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name),
                  app: try c.decode(String.self, forKey: .app),
                  layout: try c.decodeIfPresent(HeraldLayout.self, forKey: .layout) ?? .imageLeft)
        accentColor = try c.decodeIfPresent(String.self, forKey: .accentColor)
        showSubtitle = try c.decodeIfPresent(Bool.self, forKey: .showSubtitle) ?? true
        showBody = try c.decodeIfPresent(Bool.self, forKey: .showBody) ?? true
        showTimestamp = try c.decodeIfPresent(Bool.self, forKey: .showTimestamp) ?? true
        maxBodyLines = try c.decodeIfPresent(Int.self, forKey: .maxBodyLines) ?? Self.defaultMaxBodyLines
        title = try c.decodeIfPresent(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        buttons = try c.decodeIfPresent([HeraldButton].self, forKey: .buttons) ?? []
        sound = try c.decodeIfPresent(String.self, forKey: .sound)
        persistent = try c.decodeIfPresent(Bool.self, forKey: .persistent)
        timeout = try c.decodeIfPresent(Double.self, forKey: .timeout)
        snooze = try c.decodeIfPresent(Bool.self, forKey: .snooze)
        priority = try c.decodeIfPresent(String.self, forKey: .priority)
        reminder = try c.decodeIfPresent(HeraldReminder.self, forKey: .reminder)
    }
}

/// Merges a notification with the template it names (DESIGN section 6).
///
/// Precedence, per field: the payload wins, the template fills what the payload left out. For
/// `title` (a non-optional String on the wire) "left out" means empty. For `buttons` an explicit
/// empty array from the payload is a deliberate "no buttons" and wins over the template's set.
///
/// `{placeholder}` tokens are filled only in text that came from the template (a payload's own
/// text is the sender's literal and may legitimately contain braces). Values come from `metadata`
/// first (strings, plus numbers and booleans, which senders put there constantly; a dotted name
/// such as `{customer.name}` walks nested objects), then from the payload's own `title`,
/// `subtitle`, `body`, `app` and `id`. An unknown token becomes empty. Substituted text is never
/// rescanned, so a metadata value containing `{x}` stays as typed.
public enum TemplateResolver {
    public static func resolve(_ n: HeraldNotification, with t: HeraldTemplate?) -> HeraldNotification {
        guard let t else { return n }
        var out = n
        let values = Values(n)

        if n.title.isEmpty, let v = t.title { out.title = fill(v, values) }
        if n.subtitle == nil, let v = t.subtitle { out.subtitle = fill(v, values) }
        if n.body == nil, let v = t.body { out.body = fill(v, values) }
        if n.url == nil, let v = t.url { out.url = fill(v, values, urlSafe: true) }
        if n.image == nil { out.image = t.image }
        if n.buttons == nil, !t.buttons.isEmpty { out.buttons = t.buttons }
        if n.sound == nil { out.sound = t.sound }
        if n.persistent == nil { out.persistent = t.persistent }
        if n.timeout == nil { out.timeout = t.timeout }
        if n.snooze == nil { out.snooze = t.snooze }
        if n.priority == nil { out.priority = t.priority }
        if n.reminder == nil { out.reminder = t.reminder }

        out.layout = n.layout ?? t.layout
        out.accentColor = n.accentColor ?? t.accentColor
        out.showSubtitle = n.showSubtitle ?? t.showSubtitle
        out.showBody = n.showBody ?? t.showBody
        out.showTimestamp = n.showTimestamp ?? t.showTimestamp
        out.maxBodyLines = n.maxBodyLines ?? t.maxBodyLines
        return out
    }

    /// The distinct placeholder names in `text`, in order of first appearance. The template editor
    /// uses it to offer one sample-data row per token.
    public static func placeholders(in text: String) -> [String] {
        var names: [String] = []
        scan(text) { name in
            if !names.contains(name) { names.append(name) }
            return ""
        }
        return names
    }

    // MARK: Filling

    /// Where a token's value comes from: metadata first, then the payload's own fields.
    private struct Values {
        let metadata: [String: JSONValue]
        let fields: [String: String]

        init(_ n: HeraldNotification) {
            if case .object(let o)? = n.metadata { metadata = o } else { metadata = [:] }
            var f: [String: String] = ["title": n.title, "app": n.app]
            if let s = n.subtitle { f["subtitle"] = s }
            if let b = n.body { f["body"] = b }
            if let i = n.id { f["id"] = i }
            fields = f
        }

        func value(for name: String) -> String {
            if let s = Self.scalar(metadata[name]) { return s }
            if name.contains(".") {
                var current: JSONValue? = .object(metadata)
                for part in name.split(separator: ".", omittingEmptySubsequences: false) {
                    guard case .object(let o)? = current else { current = nil; break }
                    current = o[String(part)]
                }
                if let s = Self.scalar(current) { return s }
            }
            return fields[name] ?? ""
        }

        private static func scalar(_ v: JSONValue?) -> String? {
            switch v {
            case .string(let s)?: return s
            case .bool(let b)?: return b ? "true" : "false"
            case .number(let d)?:
                if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
                return String(d)
            default: return nil   // null, arrays, objects and missing keys fall through
            }
        }
    }

    private static func fill(_ text: String, _ values: Values, urlSafe: Bool = false) -> String {
        scan(text) { name in
            let v = values.value(for: name)
            return urlSafe ? urlEscaped(v) : v
        }
    }

    /// Walks `text`, replacing each well-formed `{token}` with `lookup(token)`. Braces that do not
    /// enclose a plain name (`{}`, `{ a b }`, `{"json": 1}`) are left exactly as written.
    @discardableResult
    private static func scan(_ text: String, _ lookup: (String) -> String) -> String {
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch == "{", let close = text[i...].firstIndex(of: "}") {
                let name = text[text.index(after: i)..<close]
                if isToken(name) {
                    out += lookup(String(name))
                    i = text.index(after: close)
                    continue
                }
            }
            out.append(ch)
            i = text.index(after: i)
        }
        return out
    }

    private static func isToken(_ s: Substring) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" }
    }

    /// Characters a substituted value may keep: everything that can appear in some part of a URL, including
    /// `#` so a whole link supplied in metadata (`https://x.com/a?q=1#top`) keeps its fragment. `%` is not in
    /// the set; `urlEscaped` handles it, so an existing `%20` is left alone and a bare `%` becomes `%25`.
    private static let urlLegal: CharacterSet = {
        var s = CharacterSet.urlHostAllowed
        for part in [CharacterSet.urlPathAllowed, .urlQueryAllowed, .urlFragmentAllowed, .urlUserAllowed] { s.formUnion(part) }
        s.insert(charactersIn: "#")
        s.remove(charactersIn: "%")
        return s
    }()

    /// Escapes characters that cannot appear in a URL (space, quotes, non-ASCII...), so a substituted
    /// `https://host` stays intact while "Acme Corp" becomes "Acme%20Corp" and the click target still parses.
    /// A `%` that already starts a valid escape (`%20`) is kept; any other `%` is escaped to `%25`.
    private static func urlEscaped(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "%", i + 2 < chars.count, chars[i + 1].isHexDigit, chars[i + 2].isHexDigit {
                out += "%\(chars[i + 1])\(chars[i + 2])"
                i += 3
                continue
            }
            out += c == "%" ? "%25" : (String(c).addingPercentEncoding(withAllowedCharacters: urlLegal) ?? String(c))
            i += 1
        }
        return out
    }
}
