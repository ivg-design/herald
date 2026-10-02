import Foundation

// The settings table behind `GET/PUT /v1/settings` and `GET/PUT /v1/apps/settings` (docs/reference/parity.md).
//
// One table says what each setting is: its key, its type and range, and one line for an agent. Validation is the
// table's job, so the HTTP route, the MCP tool and the tests all enforce the same rules; a setting that is not in
// the table cannot be written. The app (see `ParityHost`) only has to read and apply a key whose value already
// passed.

public enum SettingKind: Equatable, Sendable {
    case bool
    case integer(ClosedRange<Int>)
    case number(ClosedRange<Double>)
    case choice([String])
    /// A string; `nullable` lets `null` clear it (back to the default).
    case text(maxLength: Int, nullable: Bool)

    /// "bool", "integer", "number", "choice", "string".
    public var typeName: String {
        switch self {
        case .bool: return "boolean"
        case .integer: return "integer"
        case .number: return "number"
        case .choice: return "choice"
        case .text: return "string"
        }
    }
}

public struct SettingDescriptor: Sendable {
    public var key: String
    public var group: String
    public var summary: String
    public var kind: SettingKind
    /// Extra check for a string value (a voice or language name); returns the problem, or nil when it is fine.
    public var check: (@Sendable (String) -> String?)?
    /// Changing it restarts the local server (the port).
    public var restartsServer = false

    public init(_ key: String, _ group: String, _ kind: SettingKind, _ summary: String,
                restartsServer: Bool = false, check: (@Sendable (String) -> String?)? = nil) {
        self.key = key; self.group = group; self.kind = kind; self.summary = summary
        self.restartsServer = restartsServer; self.check = check
    }

    /// The descriptor as JSON, for `GET /v1/settings` (`schema`).
    public var json: [String: Any] {
        var o: [String: Any] = ["key": key, "group": group, "type": kind.typeName, "description": summary]
        switch kind {
        case .integer(let r): o["min"] = r.lowerBound; o["max"] = r.upperBound
        case .number(let r): o["min"] = r.lowerBound; o["max"] = r.upperBound
        case .choice(let values): o["values"] = values
        case .text(let maxLength, let nullable): o["maxLength"] = maxLength; if nullable { o["nullable"] = true }
        case .bool: break
        }
        if restartsServer { o["restartsServer"] = true }
        return o
    }
}

/// A value that passed validation, ready for the app to apply.
public struct ValidSetting: Equatable, Sendable {
    public var key: String
    public var value: JSONValue
}

public enum SettingsSchema {
    public static let engines = ["kokoro", "system", "off"]
    public static let corners = ["topRight", "topLeft", "bottomRight", "bottomLeft"]

    /// Everything in Settings that is not per app or quiet hours (those have their own routes).
    public static let general: [SettingDescriptor] = [
        SettingDescriptor("port", "General", .integer(1024...65535),
                          "The local API port (General > Local API). Changing it restarts the server; the new port is written to the port file.",
                          restartsServer: true),
        SettingDescriptor("launchAtLogin", "General", .bool, "Open Herald when you log in."),
        SettingDescriptor("muteAllSounds", "General", .bool, "Global mute for notification sounds (the bell menu's Mute)."),
        SettingDescriptor("stacking", "General", .choice(StackingLevel.allCases.map(\.rawValue)),
                          "How banners stack by default: byApp, byIssuer, bySender or never. An app can override it."),
        SettingDescriptor("historyCapPerApp", "General", .integer(1...HistoryStore.maxCap),
                          "How many notifications History keeps per app; the oldest beyond it are removed."),
        SettingDescriptor("tooltipLevel", "Tooltips", .choice(TooltipLevel.allCases.map(\.rawValue)),
                          "How much a tooltip says (Settings > Tooltips): nameOnly, or nameAndDescription."),
        SettingDescriptor("voiceEngine", "Voice", .choice(engines), "The speech engine: kokoro (local, natural; needs the install), system or off."),
        SettingDescriptor("voiceDefault", "Voice", .text(maxLength: 64, nullable: false), "The default voice name, for example af_heart.",
                          check: { HeraldSpeak.isValidVoice($0) ? nil : "not a valid voice name" }),
        SettingDescriptor("voiceSpeed", "Voice", .number(HeraldSpeak.speedRange), "The default speech speed, 0.5 to 2.0."),
        SettingDescriptor("voiceLang", "Voice", .text(maxLength: 16, nullable: false), "The default language code, for example en-us or en-gb.",
                          check: { HeraldSpeak.isValidLang($0) ? nil : "not a valid language code" }),
        SettingDescriptor("voiceSystem", "Voice", .text(maxLength: 256, nullable: true),
                          "The macOS voice identifier the system engine uses; null picks the system default."),
    ]

    /// Per-app settings (Settings > Apps, and Voice > Speak per app).
    public static let app: [SettingDescriptor] = [
        SettingDescriptor("sound", "Defaults", .text(maxLength: 1024, nullable: false),
                          "The app's default sound: none, a system sound name such as Glass, or a sound file path."),
        SettingDescriptor("persistent", "Defaults", .bool, "Banners stay until dismissed (true) or leave after the timeout."),
        SettingDescriptor("timeout", "Defaults", .number(0...86400), "Auto-dismiss after this many seconds; 0 never."),
        SettingDescriptor("corner", "Banners", .choice(corners), "The user's screen corner for this app; null follows the corner the app registered.",
                          check: nil),
        SettingDescriptor("display", "Banners", .text(maxLength: 32, nullable: false),
                          "Where banners appear: \"main\" or a display id from options.displays.",
                          check: { $0 == "main" || (!$0.isEmpty && $0.allSatisfy(\.isNumber)) ? nil : "use \"main\" or a display id from options.displays" }),
        SettingDescriptor("muteBanners", "Banners", .bool, "No banners for this app: its notifications go to History, unread."),
        SettingDescriptor("stacking", "Banners", .choice(StackingLevel.allCases.map(\.rawValue)),
                          "This app's stacking level; null follows the global default."),
        SettingDescriptor("speak", "Voice", .bool, "Allow this app's notifications to be spoken."),
        SettingDescriptor("voice", "Voice", .text(maxLength: 64, nullable: true), "This app's voice name; null uses the default voice.",
                          check: { HeraldSpeak.isValidVoice($0) ? nil : "not a valid voice name" }),
        SettingDescriptor("urgentBreaksQuiet", "Voice", .bool, "A priority urgent notification from this app is spoken during quiet hours."),
        SettingDescriptor("revokeCommands", "Approvals", .bool,
                          "Send true to withdraw the user's approval to run this app's command buttons. false and every grant are refused: only the user grants approvals, in Settings > Apps."),
        SettingDescriptor("revokeCallbackHost", "Approvals", .bool,
                          "Send true to withdraw the approval of this app's non-loopback callback host. Granting is refused: only the user can."),
    ]

    /// Keys that may be `null` in the app table (clearing the override).
    static let nullableApp: Set<String> = ["corner", "stacking", "voice"]

    public static func descriptor(_ key: String, in table: [SettingDescriptor]) -> SettingDescriptor? {
        table.first { $0.key == key }
    }

    /// Checks every key of `body` against `table`. All or nothing: the first problem is a 400 and nothing is applied.
    public static func validate(_ body: [String: Any], against table: [SettingDescriptor], nullable: Set<String> = []) throws -> [ValidSetting] {
        guard !body.isEmpty else { throw BackendError(400, "no settings given; send an object such as {\"muteAllSounds\":true}") }
        var out: [ValidSetting] = []
        for key in body.keys.sorted() {
            guard let d = descriptor(key, in: table) else {
                throw BackendError(400, "unknown setting: \(key) (known: \(table.map(\.key).joined(separator: ", ")))")
            }
            out.append(ValidSetting(key: key, value: try coerce(body[key] as Any, d, nullable: nullable.contains(key))))
        }
        return out
    }

    static func coerce(_ raw: Any, _ d: SettingDescriptor, nullable: Bool) throws -> JSONValue {
        func bad(_ why: String) -> BackendError { BackendError(400, "invalid value for \(d.key): \(why)") }
        if raw is NSNull {
            if nullable { return .null }
            if case .text(_, true) = d.kind { return .null }
            throw bad("null is not allowed")
        }
        switch d.kind {
        case .bool:
            guard let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw bad("true or false") }
            return .bool(n.boolValue)
        case .integer(let r):
            guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == n.doubleValue.rounded(),
                  r.contains(n.intValue) else { throw bad("an integer from \(r.lowerBound) to \(r.upperBound)") }
            return .number(Double(n.intValue))
        case .number(let r):
            guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), r.contains(n.doubleValue) else {
                throw bad("a number from \(r.lowerBound) to \(r.upperBound)")
            }
            return .number(n.doubleValue)
        case .choice(let values):
            guard let s = raw as? String, values.contains(s) else { throw bad("one of \(values.joined(separator: ", "))") }
            return .string(s)
        case .text(let maxLength, _):
            guard let s = raw as? String, !s.isEmpty || nullable, s.utf8.count <= maxLength else {
                throw bad("a non-empty string of at most \(maxLength) bytes")
            }
            if let problem = d.check?(s) { throw bad(problem) }
            return .string(s)
        }
    }
}
