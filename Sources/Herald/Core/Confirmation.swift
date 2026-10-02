import Foundation
import HeraldClient

// Inline confirmations (DESIGN 8, issue #40). A question Herald has to ask before it runs something on the user's
// behalf (send a button's payload to a host that is not this Mac, run a command, run a template's code) is drawn
// INSIDE the banner as a second row that replaces the actions row. It must never be a modal alert: an alert
// needs `NSApp.activate`, which takes the keyboard from the app the user is working in. The model here is pure so
// the wording, the buttons and the state machine (`ConfirmationFlow`) are unit tested without a window server.

/// What the user pressed on a confirmation row.
public enum ConfirmationChoice: String, Sendable, Equatable {
    /// Run (or send) this once; nothing is remembered.
    case once
    /// Run it and remember the approval (per app, per template or per host, as before).
    case always
    case cancel
    /// Acknowledge a notice (the Reminders error).
    case ok
    /// Acknowledge and open System Settings > Privacy > Reminders.
    case openSettings
}

public extension BannerConfirmationButton.Role {
    /// The `BannerButtonStyle` kind a button of this role is drawn with (a `HeraldActionStyle` name).
    var buttonStyleKind: String {
        switch self {
        case .primary: return "normal"
        case .danger: return "destructive"
        case .secondary, .cancel: return "cancel"
        }
    }
}

public struct BannerConfirmationButton: Sendable, Equatable, Identifiable {
    /// How loudly the button is drawn: `primary` is the safe answer and is tinted, `secondary` is the lasting
    /// permission (quiet on purpose, so Return-by-habit style clicking cannot grant it), `cancel` is grey.
    public enum Role: String, Sendable, Equatable { case primary, secondary, cancel
        /// The answer that goes ahead with something destructive: drawn in red.
        case danger }

    public var choice: ConfirmationChoice
    public var title: String
    public var role: Role
    public var id: String { choice.rawValue }

    public init(_ choice: ConfirmationChoice, _ title: String, _ role: Role) {
        self.choice = choice; self.title = title; self.role = role
    }
}

public struct BannerConfirmation: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case callbackHost, command, script, shortcut, templateCommand, remindersError, remindersDenied, destructiveAction
    }

    /// `caution` asks a question; `error` reports a failure.
    public enum Tone: String, Sendable, Equatable { case caution, error }

    /// Identifies this question, so a press that belongs to an earlier one (replaced meanwhile) is ignored.
    public let id: UUID
    public var kind: Kind
    public var tone: Tone
    public var title: String
    /// One short paragraph: who asks and what is at stake.
    public var detail: String
    /// The exact text that will run or be sent (the command, the script and its hash, the Shortcut and its
    /// input, the URL), shown verbatim in a monospaced box. nil for a notice.
    public var command: String?
    public var buttons: [BannerConfirmationButton]

    public init(id: UUID = UUID(), kind: Kind, tone: Tone = .caution, title: String, detail: String,
                command: String? = nil, buttons: [BannerConfirmationButton]) {
        self.id = id; self.kind = kind; self.tone = tone; self.title = title; self.detail = detail
        self.command = command; self.buttons = buttons
    }

    public func offers(_ choice: ConfirmationChoice) -> Bool { buttons.contains { $0.choice == choice } }
}

// MARK: - The four confirmations

public extension BannerConfirmation {
    /// A name or host as it appears inside a button: a very long one would push the button off the banner. The
    /// title and the exact text above the buttons always show it in full.
    private static func short(_ s: String, limit: Int = 32) -> String {
        s.count > limit ? String(s.prefix(limit - 1)) + "\u{2026}" : s
    }

    /// A callback to a host that is not this Mac. "Send once" is the default; the lasting approval (per host,
    /// kept on the app's record) is one click further away.
    static func callbackHost(name: String, host: String, url: String) -> BannerConfirmation {
        BannerConfirmation(
            kind: .callbackHost,
            title: "Send \(name)'s button action to \(host)?",
            detail: "\(name) wants Herald to POST this button's action and payload to the address below. That address is not on this Mac.",
            command: url,
            buttons: [.init(.once, "Send once", .primary), .init(.always, "Always allow \(short(host))", .secondary),
                      .init(.cancel, "Cancel", .cancel)])
    }

    /// An issuer's command, script or Shortcut, asked for the first time such a button is pressed. `text` is the
    /// exact command (`ActionRunner.describe`). "Always allow" is per app (`AppRecord.commandsConfirmed`).
    static func appCommand(kind: HeraldActionKind, name: String, text: String) -> BannerConfirmation {
        let confirmKind: Kind, title: String, detail: String
        switch kind {
        case .script:
            confirmKind = .script
            title = "Run this script for \(name)?"
            detail = "A notification sent as \(name) asks Herald to run a script from your Herald scripts folder with your user permissions. Herald cannot verify who sent it."
        case .shortcut:
            confirmKind = .shortcut
            title = "Run this Shortcut for \(name)?"
            detail = "A notification sent as \(name) asks Herald to run the Shortcut below. Shortcuts can do anything you can. Herald cannot verify who sent it."
        default:
            confirmKind = .command
            title = "Run this command for \(name)?"
            detail = "A notification sent as \(name) asks Herald to run the command below with your user permissions (/bin/zsh -lc). Herald cannot verify who sent it."
        }
        return BannerConfirmation(
            kind: confirmKind, title: title, detail: detail, command: text,
            buttons: [.init(.once, "Run once", .primary), .init(.always, "Always allow \(short(name))", .secondary),
                      .init(.cancel, "Cancel", .cancel)])
    }

    /// Code a template carries (a command, a script, a Shortcut): confirmed once per template, and again when
    /// any of it changes. `pressedText` is what runs now; `others` is the rest of the template's code, which
    /// "Always allow this template" also covers. `replacedIssuerLabel` names the issuer's own button this one
    /// replaced, since the issuer will not hear about that press.
    static func templateCommand(kind: HeraldActionKind, template: String, name: String, pressedText: String,
                                others: [String], replacedIssuerLabel: String?) -> BannerConfirmation {
        let what: String
        switch kind {
        case .script: what = "script"
        case .shortcut: what = "Shortcut"
        default: what = "command"
        }
        var detail = "This template for \(name) runs code with your user permissions: shell commands (/bin/zsh -lc), scripts and Shortcuts."
        if let r = replacedIssuerLabel {
            detail += " It replaces \(name)'s own \"\(r)\" button, so \(name) will not be told when you press it."
        }
        if !others.isEmpty { detail += " Always allow covers everything listed." }
        detail += " If any of it changes, Herald asks again."
        let shown = others.isEmpty
            ? pressedText
            : "Running now:\n\(pressedText)\n\nAlso in this template:\n" + others.joined(separator: "\n")
        return BannerConfirmation(
            kind: .templateCommand, title: "Run a \(what) from the \"\(template)\" template?", detail: detail,
            command: shown,
            buttons: [.init(.once, "Run once", .primary), .init(.always, "Always allow this template", .secondary),
                      .init(.cancel, "Cancel", .cancel)])
    }

    /// A button whose style is `destructive`: Herald asks before running it, whatever it does. `label` is the
    /// button's text; `name` the issuer or template that offers it.
    static func destructiveAction(label: String, name: String) -> BannerConfirmation {
        BannerConfirmation(
            kind: .destructiveAction,
            title: "Run \u{201C}\(short(label, limit: 40))\u{201D}?",
            detail: "This button is marked destructive, so Herald asks before it runs. It was offered by \(name).",
            buttons: [.init(.once, short(label, limit: 24), .danger), .init(.cancel, "Cancel", .cancel)])
    }

    /// "Couldn't add to Reminders". A denied permission offers a shortcut to the Privacy settings.
    static func remindersError(message: String, canOpenSettings: Bool) -> BannerConfirmation {
        var buttons = [BannerConfirmationButton(.ok, "OK", .primary)]
        if canOpenSettings { buttons.append(.init(.openSettings, "Open Privacy Settings", .secondary)) }
        return BannerConfirmation(kind: canOpenSettings ? .remindersDenied : .remindersError, tone: .error,
                                  title: "Couldn't add to Reminders", detail: message, buttons: buttons)
    }
}

// MARK: - /v1/preview

public extension BannerConfirmation {
    /// The `confirmation` of a `/v1/preview` request, so a renderer can show a banner with a question pending.
    /// A string is shorthand for `{"kind": <string>}`. `kind` is one of `callbackHost`, `command`, `script`,
    /// `shortcut`, `templateCommand`, `remindersError`, `remindersDenied` (case, `-` and `_` are ignored); the
    /// optional `name`, `host`, `url`, `command`, `template`, `others`, `replaces` and `message` fill the same
    /// builders a live confirmation uses, so what the preview draws is what the user would be asked.
    static func fromPreview(_ raw: Any, defaultName: String) throws -> BannerConfirmation {
        let kinds = Kind.allCases.map(\.rawValue).joined(separator: ", ")
        let bad = "invalid field: confirmation (a kind, or an object with a kind: \(kinds))"
        var o: [String: Any]
        switch raw {
        case let s as String: o = ["kind": s]
        case let d as [String: Any]: o = d
        default: throw BackendError(400, bad)
        }
        func text(_ key: String) throws -> String? {
            switch o[key] {
            case nil, is NSNull: return nil
            case let s as String: return s.isEmpty ? nil : s
            default: throw BackendError(400, "invalid field: confirmation.\(key) (a string)")
            }
        }
        guard let rawKind = try text("kind") else { throw BackendError(400, bad) }
        let squashed = rawKind.lowercased().filter { $0 != "-" && $0 != "_" }
        guard let kind = Kind.allCases.first(where: { $0.rawValue.lowercased() == squashed }) else { throw BackendError(400, bad) }
        let name = try text("name") ?? defaultName
        let host = try text("host") ?? "hooks.example.com"
        let command = try text("command")
        switch kind {
        case .callbackHost:
            return .callbackHost(name: name, host: host, url: try text("url") ?? "https://\(host)/herald")
        case .command:
            return .appCommand(kind: .command, name: name, text: command ?? "open -a Safari https://example.com")
        case .script:
            return .appCommand(kind: .script, name: name, text: command ?? "script: notify.sh\nsha256: 3f2a9c0e")
        case .shortcut:
            return .appCommand(kind: .shortcut, name: name,
                               text: command ?? "shortcut: Log Entry\ninput: the full notification as JSON")
        case .templateCommand:
            var others: [String] = []
            switch o["others"] {
            case nil, is NSNull: break
            case let a as [Any]:
                guard a.allSatisfy({ $0 is String }) else { throw BackendError(400, "invalid field: confirmation.others (strings)") }
                others = a.compactMap { $0 as? String }
            default: throw BackendError(400, "invalid field: confirmation.others (strings)")
            }
            return .templateCommand(kind: .command, template: try text("template") ?? "ops-alerts", name: name,
                                    pressedText: command ?? "open -a Safari https://example.com", others: others,
                                    replacedIssuerLabel: try text("replaces"))
        case .destructiveAction:
            return .destructiveAction(label: try text("label") ?? "Delete", name: name)
        case .remindersError, .remindersDenied:
            return .remindersError(message: try text("message") ?? "Herald does not have permission to use Reminders.",
                                   canOpenSettings: kind == .remindersDenied)
        }
    }
}
