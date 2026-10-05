import Foundation
import HeraldClient

/// Where a confirmation is drawn: the banner of one notification. Implemented by `BannerCenter`, which sets the
/// banner model's `confirmation` (the view then replaces the actions row with the question and the panel
/// re-measures) and clears it again. Nothing here may activate the app (DESIGN 8).
@MainActor
public protocol ConfirmationSurface: AnyObject {
    /// Shows `confirmation` on the banner of (app, id). False when that banner is not on screen.
    func presentConfirmation(_ confirmation: BannerConfirmation, app: String, id: String) -> Bool
    /// Takes the confirmation off the banner, which goes back to its actions row.
    func clearConfirmation(app: String, id: String)
}

/// The state machine behind the inline confirmations: at most ONE pending question per banner, answered by a
/// button on the banner. Each ask carries what to do when the answer lets the action go ahead (`run`, `send`),
/// so the controller's gate can be written as "ask, then continue".
///
/// Outcomes (the approval persistence is exactly what the modal alerts did):
/// - callback to another host: once sends; always remembers the host on the app's record, then sends.
/// - issuer command: once runs; always sets the app's `commandsConfirmed`, then runs.
/// - template code: once runs; always approves the pressed code and the template's other code for the template.
/// - cancel, or the banner going away or being replaced while the question is open: nothing runs, nothing is kept.
@MainActor
public final class ConfirmationFlow {
    private struct Key: Hashable { let app: String; let id: String }
    private struct Entry {
        let confirmation: BannerConfirmation
        let resolve: (ConfirmationChoice) -> Void
    }

    public weak var surface: ConfirmationSurface?
    private let registry: AppRegistry
    private let approvals: TemplateCommandApprovals
    private let changed: () -> Void
    private var pending: [Key: Entry] = [:]

    /// `changed` is called after an approval is stored (the settings views and the menu read the registry).
    public init(registry: AppRegistry, approvals: TemplateCommandApprovals, changed: @escaping () -> Void = {}) {
        self.registry = registry; self.approvals = approvals; self.changed = changed
    }

    public var pendingCount: Int { pending.count }

    /// The question open on a banner, if any.
    public func confirmation(app: String, id: String) -> BannerConfirmation? { pending[Key(app: app, id: id)]?.confirmation }

    // MARK: Asking

    /// A callback to a host that is not this Mac. `send` delivers it; it runs for "once" and "always".
    public func askCallbackHost(app: String, id: String, name: String, host: String, url: String,
                                send: @escaping () -> Void) {
        ask(.callbackHost(name: name, host: host, url: url), app: app, id: id) { [registry, changed] choice in
            switch choice {
            case .once:
                send()
            case .always:
                registry.update(app) { $0.callbackHostApproved = host }
                changed()
                send()
            default:
                break
            }
        }
    }

    /// A button styled `destructive`. `run` goes ahead for "once"; cancel (or the banner going away) does nothing.
    public func askDestructive(app: String, id: String, label: String, name: String, run: @escaping () -> Void) {
        ask(.destructiveAction(label: label, name: name), app: app, id: id) { choice in
            if choice == .once { run() }
        }
    }

    /// An issuer's command, script or Shortcut. `text` is the exact command (`ActionRunner.describe`).
    public func askCommand(app: String, id: String, name: String, kind: HeraldActionKind, text: String,
                           followUpSeconds: Int? = nil, run: @escaping () -> Void) {
        ask(.appCommand(kind: kind, name: name, text: text, followUpSeconds: followUpSeconds), app: app, id: id) { [registry, changed] choice in
            switch choice {
            case .once:
                run()
            case .always:
                registry.update(app) { $0.commandsConfirmed = true }
                changed()
                run()
            default:
                break
            }
        }
    }

    /// Code a template carries. `approvalKey` binds the approval to what was shown (the command text, the
    /// script's hash, the Shortcut and its input); `all` are every approval key of the template, so "always"
    /// approves exactly what the row listed.
    public func askTemplateCommand(app: String, id: String, template: String, name: String, kind: HeraldActionKind,
                                   pressedText: String, approvalKey: String, all: [String],
                                   replacedIssuerLabel: String?, followUpSeconds: Int? = nil, run: @escaping () -> Void) {
        let others = all.filter { $0 != approvalKey }
        let c = BannerConfirmation.templateCommand(kind: kind, template: template, name: name, pressedText: pressedText,
                                                   others: others, replacedIssuerLabel: replacedIssuerLabel,
                                                   followUpSeconds: followUpSeconds)
        ask(c, app: app, id: id) { [approvals, changed] choice in
            switch choice {
            case .once:
                run()
            case .always:
                approvals.approve(app: app, template: template, commands: [approvalKey] + others)
                changed()
                run()
            default:
                break
            }
        }
    }

    /// "Couldn't add to Reminders": a notice with OK, and Open Privacy Settings when the permission was denied.
    public func showReminderError(app: String, id: String, message: String, canOpenSettings: Bool,
                                  openSettings: @escaping () -> Void) {
        ask(.remindersError(message: message, canOpenSettings: canOpenSettings), app: app, id: id) { choice in
            if choice == .openSettings { openSettings() }
        }
    }

    /// Shows `confirmation` on the banner and remembers what to do with the answer. A question already open on
    /// the same banner is cancelled (the newer press is what the user wants now). With no banner on screen to
    /// ask on, the answer is "cancel": nothing runs without the user having seen exactly what it is.
    public func ask(_ confirmation: BannerConfirmation, app: String, id: String,
                    resolve: @escaping (ConfirmationChoice) -> Void) {
        let key = Key(app: app, id: id)
        pending.removeValue(forKey: key)?.resolve(.cancel)
        guard let surface, surface.presentConfirmation(confirmation, app: app, id: id) else {
            resolve(.cancel)
            return
        }
        pending[key] = Entry(confirmation: confirmation, resolve: resolve)
    }

    // MARK: Answering

    /// A button on the row was pressed. `confirmation` is the id of the question the button belonged to; a press
    /// for a question that has been replaced or answered is ignored, as is a choice the row did not offer.
    /// True when the press was taken.
    @discardableResult
    public func answer(app: String, id: String, confirmation: UUID? = nil, _ choice: ConfirmationChoice) -> Bool {
        let key = Key(app: app, id: id)
        guard let entry = pending[key], confirmation == nil || confirmation == entry.confirmation.id,
              entry.confirmation.offers(choice) else { return false }
        pending[key] = nil
        surface?.clearConfirmation(app: app, id: id)
        entry.resolve(choice)
        return true
    }

    /// The banner went away or was replaced (a same-id update, a dismissal, a snooze): what it asked about is no
    /// longer in front of the user, so the question is cancelled.
    public func drop(app: String, id: String) {
        let key = Key(app: app, id: id)
        guard let entry = pending.removeValue(forKey: key) else { return }
        surface?.clearConfirmation(app: app, id: id)
        entry.resolve(.cancel)
    }

    public func dropAll() {
        for key in Array(pending.keys) { drop(app: key.app, id: key.id) }
    }
}
