import Foundation

// Follow-up: run one action when a notification is left unattended (its banner is still up `after` seconds after it
// appeared). Declared, lowest to highest priority, by the issuer's manifest, by the notification itself and by the
// template (the user's choice, which replaces the others; `enabled: false` there switches an issuer's off).
// `FollowUpResolver.resolve` turns the three into one concrete action with its origin; the app's scheduler times it.
//
//   "followUp": { "after": 600, "actionRef": "forward", "enabled": true }
//   "followUp": { "after": "10m", "action": { "id": "fwd", "label": "Forward", "kind": "shortcut", "shortcut": "Forward" } }

/// A follow-up declaration. `after` is seconds (5 to 604800); on the wire it may also be a string such as "90s",
/// "10m" or "2h", which is normalised to seconds. Exactly one of `actionRef` (the id of an action the notification
/// offers, hidden ones included) or an inline `action` names what runs. `enabled: false` switches a follow-up off.
public struct HeraldFollowUp: Codable, Equatable, Sendable {
    public var after: Double?
    public var actionRef: String?
    public var action: HeraldAction?
    public var enabled: Bool?

    public static let minSeconds: Double = 5
    public static let maxSeconds: Double = 604_800
    /// The kinds a follow-up may run. An automatic link, app or reply would take focus or need the person; snooze
    /// and dismiss would hide the banner the follow-up is about.
    public static let allowedKinds: [HeraldActionKind] = [.shortcut, .script, .command, .callback]

    public init(after: Double? = nil, actionRef: String? = nil, action: HeraldAction? = nil, enabled: Bool? = nil) {
        self.after = after; self.actionRef = actionRef; self.action = action; self.enabled = enabled
    }

    /// Off when `enabled` is false.
    public var isEnabled: Bool { enabled != false }

    private enum CodingKeys: String, CodingKey { case after, actionRef, action, enabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let n = try? c.decodeIfPresent(Double.self, forKey: .after) {
            after = n
        } else if let s = try c.decodeIfPresent(String.self, forKey: .after) {
            guard let n = Self.parseDuration(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath + [CodingKeys.after],
                    debugDescription: "followUp.after '\(s)' is not a duration: seconds as a number, or a string such as \"90s\", \"10m\" or \"2h\""))
            }
            after = n
        } else {
            after = nil
        }
        let ref = try c.decodeIfPresent(String.self, forKey: .actionRef)?.trimmingCharacters(in: .whitespaces)
        actionRef = (ref?.isEmpty ?? true) ? nil : ref
        action = try c.decodeIfPresent(HeraldAction.self, forKey: .action)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(after, forKey: .after)
        try c.encodeIfPresent(actionRef, forKey: .actionRef)
        try c.encodeIfPresent(action, forKey: .action)
        try c.encodeIfPresent(enabled, forKey: .enabled)
    }

    // MARK: Durations

    /// Seconds for "600", "600s", "90 s", "10m", "10 min", "2h", "1.5h". nil for anything else (or a negative or
    /// non-finite number). Range is checked by `problems`, not here.
    public static func parseDuration(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        let units: [(String, Double)] = [("seconds", 1), ("second", 1), ("secs", 1), ("sec", 1), ("s", 1),
                                         ("minutes", 60), ("minute", 60), ("mins", 60), ("min", 60), ("m", 60),
                                         ("hours", 3600), ("hour", 3600), ("hrs", 3600), ("hr", 3600), ("h", 3600)]
        var number = s, scale = 1.0
        for (suffix, factor) in units where s.hasSuffix(suffix) {
            number = String(s.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            scale = factor
            break
        }
        guard let n = Double(number), n.isFinite, n >= 0 else { return nil }
        return n * scale
    }

    /// "90 seconds", "10 minutes", "2 hours", "1 hour 30 minutes": how the Designer, Settings and the banner say a duration.
    public static func describe(seconds raw: Double) -> String {
        let s = Int(raw.rounded())
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        guard s >= 60, s % 60 == 0 else { return unit(s, "second") }
        guard s >= 3600 else { return unit(s / 60, "minute") }
        let h = s / 3600, m = (s % 3600) / 60
        return m == 0 ? unit(h, "hour") : unit(h, "hour") + " " + unit(m, "minute")
    }

    // MARK: Validation

    /// Everything wrong with this declaration, one line each, paths relative to `path` (for example `followUp.after`).
    /// `actions` are the action ids `actionRef` may name; nil skips that check (the list is only known per notification).
    /// `timeout`: the banner's auto-dismiss, when known; shorter than `after` means it never follows up (a warning).
    public func problems(path p: String = "followUp", knownActionIDs: [String]? = nil,
                         timeout: Double? = nil) -> [(message: String, isError: Bool, path: String)] {
        var out: [(String, Bool, String)] = []
        guard isEnabled else { return [] }   // switched off: nothing else matters
        if let a = after {
            if !a.isFinite || a < Self.minSeconds || a > Self.maxSeconds {
                out.append(("after must be \(Int(Self.minSeconds)) to \(Int(Self.maxSeconds)) seconds (7 days)", true, "\(p).after"))
            }
        } else {
            out.append(("a follow-up needs 'after': seconds, or a string such as \"10m\"", true, "\(p).after"))
        }
        switch (actionRef, action) {
        case (nil, nil):
            out.append(("a follow-up needs 'actionRef' (the id of an action the banner offers) or an inline 'action'", true, p))
        case (.some, .some):
            out.append(("a follow-up names its action once: 'actionRef' or 'action', not both", true, p))
        case (.some(let ref), nil):
            if let ids = knownActionIDs, !ids.contains(where: { $0.caseInsensitiveCompare(ref) == .orderedSame }) {
                out.append(("actionRef '\(ref)' is not an action this app offers (\(ids.joined(separator: ", ")))", true, "\(p).actionRef"))
            }
        case (nil, .some(let a)):
            if let why = Self.kindProblem(a.kind) { out.append((why, true, "\(p).action.kind")) }
            switch a.kind {
            case .shortcut where (a.shortcut ?? "").trimmingCharacters(in: .whitespaces).isEmpty:
                out.append(("a shortcut follow-up needs the name of an installed Shortcut", true, "\(p).action.shortcut"))
            case .script:
                let s = (a.script ?? "").trimmingCharacters(in: .whitespaces)
                if s.isEmpty { out.append(("a script follow-up needs the name of a file in Herald's scripts folder", true, "\(p).action.script")) }
                else if !HeraldScriptName.isPlain(s) { out.append(("script must be a plain file name in Herald's scripts folder, not a path", true, "\(p).action.script")) }
            case .command where (a.command ?? "").trimmingCharacters(in: .whitespaces).isEmpty:
                out.append(("a command follow-up needs a command", true, "\(p).action.command"))
            default: break
            }
        }
        if let t = timeout, t > 0, let a = after, a >= t {
            out.append(("the banner closes by itself after \(Self.describe(seconds: t)), before the follow-up's \(Self.describe(seconds: a)): it never follows up", false, "\(p).after"))
        }
        return out
    }

    /// Why `kind` cannot be a follow-up, or nil when it can.
    public static func kindProblem(_ kind: HeraldActionKind) -> String? {
        guard !allowedKinds.contains(kind) else { return nil }
        let why: String
        switch kind {
        case .url, .openApp: why = "it would take focus while you are away"
        case .reply: why = "it needs you at the banner"
        case .snooze, .dismiss: why = "it would hide the banner the follow-up is about"
        default: why = "it cannot run unattended"
        }
        return "a follow-up cannot be a '\(kind.rawValue)' action (\(why)); use shortcut, script, command or callback"
    }
}

/// What a follow-up did, kept on the notification's History record (`HeraldHistoryItem.followUp`).
public struct HeraldFollowUpRecord: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        /// The action ran and succeeded.
        case ran
        /// It ran and failed, or could not run; `detail` says why.
        case failed
        /// The action needs an approval the person has not given; the question is on the banner.
        case waitingForApproval
    }
    /// When the follow-up fired (its timer ran out).
    public var ranAt: Date
    /// The action's label.
    public var action: String
    public var actionId: String?
    public var kind: HeraldActionKind?
    public var outcome: Outcome
    public var detail: String?
    /// How long the banner had been up, unattended, when it fired.
    public var unattendedSeconds: Int?

    public init(ranAt: Date, action: String, actionId: String? = nil, kind: HeraldActionKind? = nil, outcome: Outcome,
                detail: String? = nil, unattendedSeconds: Int? = nil) {
        self.ranAt = ranAt; self.action = action; self.actionId = actionId; self.kind = kind
        self.outcome = outcome; self.detail = detail; self.unattendedSeconds = unattendedSeconds
    }

    /// The detail of a follow-up that never ran because the app may not run commands at all.
    public static func notAllowedDetail(name: String) -> String { "\(name) is not allowed to run commands, scripts and Shortcuts" }
    /// True for the failure `notAllowedDetail` describes: the one the person fixes in Settings > Apps.
    public var isNotAllowed: Bool { outcome == .failed && detail?.hasSuffix("is not allowed to run commands, scripts and Shortcuts") == true }

    /// The quiet line under the banner's grid, always a full sentence:
    /// "Follow-up ran: Forward at 14:05.", "Follow-up failed: Forward (exit 1).",
    /// "Follow-up did not run: allow Acme to run commands in Settings > Apps." nil while it waits for approval
    /// (the question is on the banner then).
    public func bannerLine(appName: String? = nil, timeFormatter: (Date) -> String) -> String? {
        switch outcome {
        case .ran: return "Follow-up ran: \(action) at \(timeFormatter(ranAt))."
        case .failed:
            if isNotAllowed { return "Follow-up did not run: allow \(appName ?? "this app") to run commands in Settings > Apps." }
            if let d = detail, !d.isEmpty { return "Follow-up failed: \(action) (\(d))." }
            return "Follow-up failed: \(action)."
        case .waitingForApproval: return nil
        }
    }
}

/// Where a follow-up was declared.
public enum HeraldFollowUpSource: String, Codable, Sendable {
    case manifest, notification, template
}

/// A follow-up resolved for one notification: what runs, after how long, under which rules.
public struct HeraldResolvedFollowUp: Equatable, Sendable {
    public var after: Double
    public var action: HeraldAction
    /// `.issuer` runs under the app's "Allow this app to run commands, scripts and Shortcuts"; `.template` under the
    /// template's one-time approval.
    public var origin: HeraldActionOrigin
    public var source: HeraldFollowUpSource
    public init(after: Double, action: HeraldAction, origin: HeraldActionOrigin, source: HeraldFollowUpSource) {
        self.after = after; self.action = action; self.origin = origin; self.source = source
    }
}

public enum FollowUpResolver {
    /// The declaration that applies: the template's when it has one (its `enabled: false` switches the others off),
    /// else the notification's, else the manifest's. nil when none applies or the one that applies is switched off.
    public static func declaration(manifest: HeraldManifest?, notification: HeraldNotification?,
                                   template: HeraldTemplate?) -> (HeraldFollowUp, HeraldFollowUpSource)? {
        let chosen: (HeraldFollowUp, HeraldFollowUpSource)?
        if let t = template?.followUp { chosen = (t, .template) }
        else if let n = notification?.followUp { chosen = (n, .notification) }
        else if let m = manifest?.followUp { chosen = (m, .manifest) }
        else { chosen = nil }
        guard let c = chosen, c.0.isEnabled else { return nil }
        return c
    }

    /// The one follow-up for a notification, or nil. `candidates` are the actions an `actionRef` may name: everything
    /// the notification offers, hidden ones included (`candidates(notification:manifest:template:)`).
    ///
    /// Origin: an inline action is the declarer's (`.issuer` for the manifest and the notification, `.template` for the
    /// template). An `actionRef` runs as `.issuer` when either the declarer or the action it names is the issuer's, so
    /// a template cannot launder an issuer's command into its own approval, nor an issuer trigger the user's code.
    /// A declaration that is invalid (no action, a kind that cannot follow up, `after` out of range) resolves to nil.
    public static func resolve(manifest: HeraldManifest?, notification: HeraldNotification?, template: HeraldTemplate?,
                               candidates: [HeraldResolvedAction]) -> HeraldResolvedFollowUp? {
        guard let (decl, source) = declaration(manifest: manifest, notification: notification, template: template),
              decl.problems(path: "followUp").allSatisfy({ !$0.isError }), let after = decl.after else { return nil }
        let declarer: HeraldActionOrigin = source == .template ? .template : .issuer
        let action: HeraldAction, origin: HeraldActionOrigin
        if let a = decl.action {
            action = a; origin = declarer
        } else if let ref = decl.actionRef,
                  let found = candidates.first(where: { $0.action.id.caseInsensitiveCompare(ref) == .orderedSame })
                    ?? candidates.first(where: { $0.action.label.caseInsensitiveCompare(ref) == .orderedSame }) {
            action = found.action
            origin = (declarer == .issuer || found.origin == .issuer) ? .issuer : .template
        } else {
            return nil
        }
        guard HeraldFollowUp.kindProblem(action.kind) == nil else { return nil }
        return HeraldResolvedFollowUp(after: after, action: action, origin: origin, source: source)
    }

    /// Every action a follow-up's `actionRef` may name for `notification`: what the banner offers after the template's
    /// rules, then the actions the rules hid (issuer buttons, origin `.issuer`), every action the manifest declares, and
    /// the template's own adds.
    public static func candidates(notification n: HeraldNotification, manifest: HeraldManifest?,
                                  template: HeraldTemplate?) -> [HeraldResolvedAction] {
        var list = ActionResolver.offered(notification: n, manifest: manifest, template: template)
        let source = ActionResolver.issuerSource(for: n, manifest: manifest)
        let unruled = ActionResolver.resolveDetailed(issuer: source.buttons, ids: source.ids, rules: [],
                                                     issuerOrigin: ActionResolver.buttonsCameFromTemplate(n, template) ? .template : .issuer)
        for a in unruled where !list.contains(where: { $0.action.id == a.action.id }) { list.append(a) }
        // Every action the manifest declares, even one this notification does not show (the issuer's default follow-up
        // names its own action).
        if let m = manifest {
            for (i, b) in m.actions.enumerated() where !list.contains(where: { $0.action.id == m.actionID(at: i) }) {
                list.append(HeraldResolvedAction(action: HeraldAction(button: b, id: m.actionID(at: i)), origin: .issuer))
            }
        }
        for a in (template?.actionRules ?? []).compactMap(\.add) where !list.contains(where: { $0.action.id == a.id }) {
            list.append(HeraldResolvedAction(action: a, origin: .template))
        }
        return list
    }

    /// The same without a notification (the Designer, `set_follow_up`): every action the manifest declares, the
    /// template's rules and adds, and its inline actions.
    public static func sampleCandidates(manifest: HeraldManifest?, template: HeraldTemplate?) -> [HeraldResolvedAction] {
        let sample = ActionResolver.sampleSource(manifest: manifest)
        var list = ActionResolver.resolveDetailed(issuer: sample.buttons, ids: sample.ids, rules: template?.actionRules ?? [])
        for a in ActionResolver.resolveDetailed(issuer: sample.buttons, ids: sample.ids, rules: [])
        where !list.contains(where: { $0.action.id == a.action.id }) { list.append(a) }
        // Manifest actions that `fillingLinks` left out (a link with no sample value) still exist.
        if let m = manifest {
            for (i, b) in m.actions.enumerated() where !list.contains(where: { $0.action.id == m.actionID(at: i) }) {
                list.append(HeraldResolvedAction(action: HeraldAction(button: b, id: m.actionID(at: i)), origin: .issuer))
            }
        }
        for a in (template?.actionRules ?? []).compactMap(\.add) where !list.contains(where: { $0.action.id == a.id }) {
            list.append(HeraldResolvedAction(action: a, origin: .template))
        }
        for cell in template?.cells ?? [] {
            for a in cell.component.inlineActions where !list.contains(where: { $0.action == a }) {
                list.append(HeraldResolvedAction(action: a, origin: .template))
            }
        }
        return list
    }

    /// The follow-up a template would run, resolved against sample data (no notification): for the Designer, the
    /// approvals list and `set_follow_up`.
    public static func resolveForTemplate(manifest: HeraldManifest?, template: HeraldTemplate?) -> HeraldResolvedFollowUp? {
        resolve(manifest: manifest, notification: nil, template: template,
                candidates: sampleCandidates(manifest: manifest, template: template))
    }
}
