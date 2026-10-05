import CryptoKit
import Foundation

// Running two-way actions (DESIGN section 7.3). Foundation only, so the whole decision path is unit tested
// without AppKit: AppController asks `plan` what an action means, `gate` whether it needs the user's say-so,
// shows the alerts itself, and hands process work to `run`.
//
//   url       open a link (only http, https, mailto; `{token}` placeholders are filled for template actions)
//   callback  POST to the issuer's callback URL (the template's `extra` values ride along in the payload)
//   command   /bin/zsh -lc "<command>"; never interpolated, the data comes on stdin and in HERALD_* variables
//   script    a file under Application Support/Herald/scripts; the merged payload JSON on stdin
//   shortcut  /usr/bin/shortcuts run "<name>" --input-path <temp file>: text from `input`, else the JSON
//   dismiss / snooze   handled by the controller
//
// Every process gets the merged payload (issuer fields + metadata + the template's `extra`), a 30 s timeout,
// and its output lands in ~/Library/Logs/Herald/actions.log.

// MARK: - Invocation

/// Everything an action may read: the notification as delivered, its resolved fields and the template's
/// authored `extra` values.
public struct ActionInvocation: Sendable {
    public var notification: HeraldNotification
    public var fields: [String: HeraldFieldValue]
    public var extra: [String: String]
    /// Name of the template the notification used, if any.
    public var template: String?
    /// Local copy of the notification's image, if one was cached.
    public var imagePath: String?
    /// Set when a follow-up runs the action (the banner was left up this long), nil for a pressed button. The action
    /// then also reads `{herald.followUp}` and `{herald.unattendedSeconds}`, and the JSON carries
    /// `"herald": {"followUp": true, "unattendedSeconds": N}`, so one Shortcut can serve a button and a follow-up.
    public var unattendedSeconds: Int?

    public init(notification: HeraldNotification, fields: [String: HeraldFieldValue] = [:],
                extra: [String: String] = [:], template: String? = nil, imagePath: String? = nil,
                unattendedSeconds: Int? = nil) {
        self.notification = notification; self.fields = fields; self.extra = extra
        self.template = template; self.imagePath = imagePath; self.unattendedSeconds = unattendedSeconds
        if let u = unattendedSeconds {
            self.fields["herald.followUp"] = .bool(true)
            self.fields["herald.unattendedSeconds"] = .number(Double(u))
        }
    }

    /// The merged payload as JSON: `ActionResolver.mergedPayload` plus the template name, the cached image path and,
    /// for a follow-up, the `herald` object.
    public func payloadJSON(action: HeraldAction?) -> Data {
        var value = ActionResolver.mergedPayload(notification: notification, fields: fields, extra: extra, action: action)
        if case .object(var o) = value {
            if let t = template, !t.isEmpty { o["template"] = .string(t) }
            if let p = imagePath, !p.isEmpty { o["imagePath"] = .string(p) }
            o["herald"] = .object(["followUp": .bool(unattendedSeconds != nil),
                                   "unattendedSeconds": unattendedSeconds.map { .number(Double($0)) } ?? .null])
            value = .object(o)
        }
        return (try? HeraldJSON.encoder().encode(value)) ?? Data("{}".utf8)
    }
}

/// An action that cannot run; `reason` is short enough for the banner's "Action failed" line.
public struct ActionError: Error, Equatable, Sendable, LocalizedError {
    public var reason: String
    public init(_ reason: String) { self.reason = reason }
    public var errorDescription: String? { reason }
}

/// What the user has to agree to before an action runs.
public enum ActionGate: Equatable, Sendable {
    /// Nothing to ask.
    case open
    /// The issuer asked Herald to run code: needs the app's command permission (`CommandPermission`).
    case appPermission
    /// Code the template's author (the user, or an agent working for them) wrote: a shell command, a script
    /// file or a Shortcut. It needs one confirmation per template (`TemplateCommandApprovals`), and the
    /// approval is bound to what was shown: the command text, the script file's SHA-256, the Shortcut's name
    /// and input. `subject` is the command, the script name or the Shortcut name.
    case templateConfirmation(kind: HeraldActionKind, subject: String)
}

/// The outcome of `ActionRunner.authorization`.
public enum ActionAuthorization: Equatable, Sendable {
    case run
    /// The app never registered with `allowCommands`: nothing runs.
    case denied(String)
    /// The app may ask, the person has not agreed yet: the banner asks, showing `text`.
    case askApp(text: String)
    /// Template code not approved yet: the banner asks once for the template (`all` are every key it approves).
    case askTemplate(approvalKey: String, all: [String], text: String)
}

// MARK: - Plans

/// A process to run, described as data.
public struct ActionProcessSpec: Equatable, Sendable {
    public enum Kind: String, Sendable { case command, script, shortcut }
    /// In `arguments`, replaced by the path of the temporary input file when the process is launched.
    public static let inputPathToken = "{{input-path}}"

    public var kind: Kind
    public var executable: String
    public var arguments: [String]
    /// Becomes the process's standard input (through a temporary file, so a program that never reads it is not blocked).
    public var stdin: Data?
    /// Written to a temporary file whose path replaces `inputPathToken` (the shortcut's `--input-path`).
    public var inputFile: Data?
    public var inputFileExtension: String
    public var environment: [String: String]
    public var workingDirectory: URL?
    /// What the log shows after `$`.
    public var display: String
    public var timeout: TimeInterval

    public init(kind: Kind, executable: String, arguments: [String], stdin: Data? = nil, inputFile: Data? = nil,
                inputFileExtension: String = "txt", environment: [String: String] = [:],
                workingDirectory: URL? = nil, display: String, timeout: TimeInterval) {
        self.kind = kind; self.executable = executable; self.arguments = arguments; self.stdin = stdin
        self.inputFile = inputFile; self.inputFileExtension = inputFileExtension
        self.environment = environment; self.workingDirectory = workingDirectory
        self.display = display; self.timeout = timeout
    }
}

public enum ActionPlan: Equatable, Sendable {
    case openURL(URL)
    case callback(HeraldCallback)
    case process(ActionProcessSpec)
    case dismiss
    case snooze(minutes: Double)
    /// Bring an application to the front. `bundleId` and `path` are the action's own, already checked for shape; the
    /// controller adds the manifest, the registration and the app name behind them (`HeraldOpenAppResolver`).
    case openApp(bundleId: String?, path: String?)
    /// Show the inline reply field on the banner (`HeraldReply` carries the placeholder and an optional callback).
    case reply(HeraldReply)
}

// MARK: - Launching processes

/// What a launcher is asked to start. Files are already in place when it is called.
public struct ActionProcessRequest: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    /// Added to the launching process's own environment.
    public var environment: [String: String]
    /// Connected to standard input; nil means /dev/null.
    public var stdinFile: URL?
    public var workingDirectory: URL
    public var timeout: TimeInterval
    public var outputLimit: Int
}

/// Starts a process and reports how it ended. Injectable so tests need no real programs.
public protocol ActionProcessLauncher: Sendable {
    func launch(_ request: ActionProcessRequest) async -> CommandResult
}

/// The real thing: `Process`, output into a temp file (a command that backgrounds something leaves a child
/// holding a pipe, and reading the pipe to EOF would wait for that child for ever), SIGTERM at the deadline
/// and SIGKILL two seconds later.
public struct SystemProcessLauncher: ActionProcessLauncher {
    public init() {}

    public func launch(_ request: ActionProcessRequest) async -> CommandResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: Self.runBlocking(request)) }
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    private static func runBlocking(_ r: ActionProcessRequest) -> CommandResult {
        let started = Date()
        func failed(_ message: String) -> CommandResult {
            CommandResult(exitCode: -1, signaled: false, timedOut: false, launchError: message,
                          output: "", truncated: false, duration: Date().timeIntervalSince(started))
        }
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("herald-action-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: outURL.path, contents: nil),
              let out = try? FileHandle(forWritingTo: outURL) else { return failed("cannot create an output file") }
        defer { try? out.close(); try? FileManager.default.removeItem(at: outURL) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: r.executable)
        p.arguments = r.arguments
        p.currentDirectoryURL = r.workingDirectory
        var env = ProcessInfo.processInfo.environment
        for (k, v) in r.environment { env[k] = v }
        p.environment = env
        if let f = r.stdinFile {
            guard let h = try? FileHandle(forReadingFrom: f) else { return failed("cannot open the input file") }
            p.standardInput = h
        } else {
            p.standardInput = FileHandle.nullDevice
        }
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return failed(error.localizedDescription) }

        let timedOut = Flag()
        let killer = DispatchWorkItem {
            guard p.isRunning else { return }
            timedOut.set()
            p.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + r.timeout, execute: killer)
        p.waitUntilExit()
        killer.cancel()

        var data = Data()
        var truncated = false
        if let reader = try? FileHandle(forReadingFrom: outURL) {
            data = (try? reader.read(upToCount: r.outputLimit + 1)) ?? Data()
            try? reader.close()
            if data.count > r.outputLimit { data = data.prefix(r.outputLimit); truncated = true }
        }
        return CommandResult(exitCode: p.terminationStatus, signaled: p.terminationReason == .uncaughtSignal,
                             timedOut: timedOut.isSet, launchError: nil,
                             output: String(decoding: data, as: UTF8.self), truncated: truncated,
                             duration: Date().timeIntervalSince(started))
    }
}

// MARK: - Log

/// `~/Library/Logs/Herald/actions.log`: every script, command and shortcut run, with its output. The file
/// itself is a `CommandLog` (one backup generation, so it cannot grow without bound).
public enum ActionLog {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Herald/actions.log")
    }

    /// One line a label or id may not break: sender-supplied text must not be able to forge a log line.
    static func oneLine(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : $0 }))
            .replacingOccurrences(of: "\"", with: "'")
    }

    public static func entry(display: String, kind: String, origin: HeraldActionOrigin?, context: CommandContext,
                             result: CommandResult, at date: Date = Date()) -> String {
        var s = "\(ISODate.string(from: date)) app=\(oneLine(context.app)) id=\(oneLine(context.notificationId)) "
        s += "action=\"\(oneLine(context.action))\" kind=\(kind)"
        if let o = origin { s += " origin=\(o.rawValue)" }
        s += " result=\"\(result.summary)\" duration=\(String(format: "%.2f", result.duration))s\n"
        s += "$ \(display)\n"
        if !result.output.isEmpty {
            s += result.output.hasSuffix("\n") ? result.output : result.output + "\n"
            if result.truncated { s += "[output truncated]\n" }
        }
        s += "---\n"
        return s
    }

    /// The line a follow-up leaves in the log: that it fired, ran, failed or waits for approval (a script, command or
    /// Shortcut it ran also has its own entry with the output).
    public static func followUpEntry(app: String, notificationId: String, action: HeraldAction, origin: HeraldActionOrigin,
                                     record: HeraldFollowUpRecord, at date: Date = Date()) -> String {
        let what: String
        switch record.outcome {
        case .ran: what = "follow-up ran"
        case .failed: what = "follow-up failed"
        case .waitingForApproval: what = "follow-up waiting for approval"
        }
        var s = "\(ISODate.string(from: date)) app=\(oneLine(app)) id=\(oneLine(notificationId)) "
        s += "action=\"\(oneLine(action.label))\" kind=\(action.kind.rawValue) origin=\(origin.rawValue) result=\"\(what)"
        if let d = record.detail, !d.isEmpty { s += ": \(oneLine(d))" }
        s += "\""
        if let u = record.unattendedSeconds { s += " unattended=\(u)s" }
        return s + "\n---\n"
    }
}

// MARK: - Runner

public final class ActionRunner: Sendable {
    public static let defaultTimeout: TimeInterval = 30
    public static let defaultShortcutsPath = "/usr/bin/shortcuts"
    public static let defaultSnoozeMinutes = Double(HeraldAction.defaultSnoozeMinutes)

    public static var defaultScriptsDirectory: URL {
        HeraldPaths.defaultSupportDirectory.appendingPathComponent("scripts", isDirectory: true)
    }

    public let scriptsDirectory: URL
    public let shell: String
    public let shellArguments: [String]
    public let shortcutsPath: String
    public let timeout: TimeInterval
    public let outputLimit: Int
    public let launcher: any ActionProcessLauncher
    public let log: CommandLog

    public init(scriptsDirectory: URL = ActionRunner.defaultScriptsDirectory,
                shell: String = CommandRunner.defaultShell,
                shellArguments: [String] = CommandRunner.defaultShellArguments,
                shortcutsPath: String = ActionRunner.defaultShortcutsPath,
                timeout: TimeInterval = ActionRunner.defaultTimeout, outputLimit: Int = 64 * 1024,
                launcher: any ActionProcessLauncher = SystemProcessLauncher(),
                log: CommandLog = CommandLog(url: ActionLog.defaultURL)) {
        self.scriptsDirectory = scriptsDirectory; self.shell = shell; self.shellArguments = shellArguments
        self.shortcutsPath = shortcutsPath; self.timeout = timeout; self.outputLimit = outputLimit
        self.launcher = launcher; self.log = log
    }

    /// Creates the scripts folder if it is missing (the app calls it at launch and from Settings).
    @discardableResult
    public func ensureScriptsDirectory() -> Bool {
        (try? FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)) != nil
    }

    // MARK: Gate

    /// What must be agreed before `action` runs. Code the issuer asks for (a command, and a script or a
    /// shortcut should an issuer ever name one) needs the app's command permission. Code the template carries
    /// (a command, a script or a Shortcut) is confirmed once per template. `shortcuts run` is headless, so a
    /// Shortcut is as able to do harm as a script and is not exempt.
    public static func gate(for action: HeraldAction, origin: HeraldActionOrigin) -> ActionGate {
        switch (action.kind, origin) {
        case (.command, .template): return .templateConfirmation(kind: .command, subject: action.command ?? "")
        case (.script, .template): return .templateConfirmation(kind: .script, subject: action.script ?? "")
        case (.shortcut, .template): return .templateConfirmation(kind: .shortcut, subject: action.shortcut ?? "")
        case (.command, .issuer), (.script, .issuer), (.shortcut, .issuer): return .appPermission
        default: return .open
        }
    }

    /// What has to happen before `action` runs, given the app's record and the template approvals: run now, refuse
    /// (the app never asked to run commands), or ask the person on the banner. A pressed button and a follow-up both go
    /// through this, so a follow-up never runs code a button press would have asked about.
    public func authorization(for action: HeraldAction, origin: HeraldActionOrigin, app: String, record: AppRecord?,
                              template: HeraldTemplate?, templateName: String,
                              approvals: TemplateCommandApprovals) -> ActionAuthorization {
        switch Self.gate(for: action, origin: origin) {
        case .open:
            return .run
        case .appPermission:
            switch CommandPermission.evaluate(record) {
            case .denied(let why): return .denied(why)
            case .allowed: return .run
            case .needsConfirmation:
                // Name exactly what will run: the command, the script with its hash, the Shortcut with its input.
                return .askApp(text: action.kind == .command ? Self.describe(action) : confirmationText(for: action))
            }
        case .templateConfirmation:
            // The approval key binds to the command text, the script file's hash or the Shortcut's name and input.
            guard let key = approvalKey(for: action) else { return .run }
            if approvals.isApproved(app: app, template: templateName, command: key) { return .run }
            let all = template.map { templateApprovalKeys(of: $0) } ?? [key]
            return .askTemplate(approvalKey: key, all: all.contains(key) ? all : [key] + all, text: confirmationText(for: action))
        }
    }

    /// A button styled `destructive` asks the user before it runs, whatever its kind (the question is the inline
    /// row of `ConfirmationFlow.askDestructive`, ahead of any gate of the action itself).
    public static func confirmsBeforeRunning(_ action: HeraldAction) -> Bool {
        HeraldActionStyle.asksConfirmation(action.style)
    }

    /// The action as the confirmation alert and the log show it.
    public static func describe(_ action: HeraldAction) -> String {
        switch action.kind {
        case .command: return action.command ?? ""
        case .script: return "script: \(action.script ?? "")"
        case .shortcut: return "shortcut: \(action.shortcut ?? "")"
        case .url: return action.url ?? ""
        case .callback: return "callback"
        case .dismiss: return "dismiss"
        case .snooze: return "snooze \(action.snoozeMinutes ?? HeraldAction.defaultSnoozeMinutes) min"
        case .openApp: return "open app: " + (action.bundleId ?? action.path ?? "the issuing application")
        case .reply: return "reply"
        }
    }

    // MARK: Approval keys

    /// The SHA-256 of the script file `name` names under the scripts folder, as lowercase hex. "missing" when
    /// the file does not resolve or cannot be read, so a script that is created or removed later no longer
    /// matches an earlier approval.
    func scriptHash(_ name: String?) -> String {
        guard case .success(let url) = resolveScript(name),
              let data = try? Data(contentsOf: url) else { return "missing" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// What a per-template approval is bound to: the command text, the script name with the file's SHA-256, or
    /// the Shortcut's name with its input. Editing any of them makes the approval stop matching, so an action
    /// that was approved cannot be swapped for another. nil for kinds that run no code.
    public func approvalKey(for action: HeraldAction) -> String? {
        switch action.kind {
        case .command:
            let c = (action.command ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return c.isEmpty ? nil : c
        case .script:
            let n = (action.script ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? nil : "script: \(n) sha256:\(scriptHash(n))"
        case .shortcut:
            let n = (action.shortcut ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty else { return nil }
            let input = (action.input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return "shortcut: \(n) input: " + (input.isEmpty ? "<full notification JSON>" : input)
        case .url, .callback, .dismiss, .snooze, .openApp, .reply:
            return nil
        }
    }

    /// The approval keys of everything in `t` that runs code, de-duplicated, in order.
    public func templateApprovalKeys(of t: HeraldTemplate) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for a in Self.templateOwnActions(of: t) {
            if let k = approvalKey(for: a), seen.insert(k).inserted { out.append(k) }
        }
        return out
    }

    /// What the confirmation alert shows for an action: the command, or the script's name, hash and the start
    /// of its text, or the Shortcut's name and input.
    public func confirmationText(for action: HeraldAction, limit: Int = 4000) -> String {
        switch action.kind {
        case .script:
            let name = (action.script ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var s = "script: \(name)\nsha256: \(scriptHash(name))"
            if case .success(let url) = resolveScript(name), let data = try? Data(contentsOf: url) {
                let text = String(decoding: data.prefix(limit), as: UTF8.self)
                s += "\n\n" + text + (data.count > limit ? "\n[... \(data.count - limit) more bytes]" : "")
            }
            return s
        case .shortcut:
            let input = (action.input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return "shortcut: \(action.shortcut ?? "")\ninput: " + (input.isEmpty ? "the full notification as JSON" : input)
        default:
            return Self.describe(action)
        }
    }

    /// The label of the issuer's button that a template action with the same id has replaced, or nil when it
    /// replaced nothing (or the buttons are the template's own).
    public static func replacedIssuerLabel(for action: HeraldAction, notification n: HeraldNotification,
                                           manifest: HeraldManifest?, template: HeraldTemplate?) -> String? {
        guard !buttonsCameFromTemplate(n, template) else { return nil }
        return issuerLabel(id: action.id, notification: n, manifest: manifest)
    }

    // MARK: Resolving what a banner offers

    /// The legacy v1 button as an action, with v1's precedence (url, then command, then callback, else dismiss).
    public static func legacyAction(_ b: HeraldButton) -> HeraldAction {
        let kind: HeraldActionKind = b.reply != nil ? .reply : b.url != nil ? .url : b.command != nil ? .command
            : b.script != nil ? .script : b.shortcut != nil ? .shortcut
            : b.callback != nil ? .callback : b.openApp != nil ? .openApp : .dismiss
        return HeraldAction(id: HeraldAction.slug(b.label), label: b.label, kind: kind, style: b.style,
                            url: b.url, callback: b.callback, command: b.command, script: b.script, shortcut: b.shortcut,
                            input: b.input, bundleId: b.openApp?.bundleId, path: b.openApp?.path, reply: b.reply)
    }

    /// Every action a banner for `notification` can offer, with its origin: the issuer's buttons after the
    /// template's rules, then the template's inline component actions that the rules did not already produce.
    public static func resolvedActions(notification n: HeraldNotification, manifest: HeraldManifest?,
                                       template: HeraldTemplate?) -> [HeraldResolvedAction] {
        ActionResolver.offered(notification: n, manifest: manifest, template: template)
    }

    static func buttonsCameFromTemplate(_ n: HeraldNotification, _ template: HeraldTemplate?) -> Bool {
        ActionResolver.buttonsCameFromTemplate(n, template)
    }

    /// The follow-up for a delivered notification (`FollowUpResolver`), with every action it may name.
    public static func followUp(notification n: HeraldNotification, manifest: HeraldManifest?,
                                template: HeraldTemplate?) -> HeraldResolvedFollowUp? {
        FollowUpResolver.resolve(manifest: manifest, notification: n, template: template,
                                 candidates: FollowUpResolver.candidates(notification: n, manifest: manifest, template: template))
    }

    /// Finds the pressed action in `list`: identical first, then the same id and kind (a view may have filled
    /// a `{token}` in the label). nil means "not something this notification offers".
    public static func match(_ pressed: HeraldAction, in list: [HeraldResolvedAction]) -> HeraldResolvedAction? {
        list.first { $0.action == pressed } ?? list.first { $0.action.id == pressed.id && $0.action.kind == pressed.kind }
    }

    /// The label the issuer sent for the issuer action `id`, before any template rule relabelled it.
    public static func issuerLabel(id: String, notification n: HeraldNotification, manifest: HeraldManifest?) -> String? {
        let source = ActionResolver.issuerSource(for: n, manifest: manifest)
        return ActionResolver.resolveDetailed(issuer: source.buttons, ids: source.ids, rules: [])
            .first { $0.action.id == id }?.action.label
    }

    /// Every action a template carries itself: rule `add`s, inline component actions and its v1 default
    /// `buttons`. This is the template author's code and what the per-template confirmation covers.
    static func templateOwnActions(of t: HeraldTemplate) -> [HeraldAction] {
        var all: [HeraldAction] = t.actionRules.compactMap(\.add)
        for cell in t.cells { all += cell.component.inlineActions }
        all += t.buttons.map { legacyAction($0) }
        // An inline follow-up action is the template's own code too: "Always allow" covers it with the rest.
        if let a = t.followUp?.action, t.followUp?.isEnabled == true { all.append(a) }
        return all
    }

    /// The shell commands a template carries itself (rule `add`s, inline component actions and v1 default
    /// `buttons`), trimmed and de-duplicated.
    public static func templateCommands(of t: HeraldTemplate) -> [String] {
        let all = templateOwnActions(of: t)
        var seen = Set<String>(), out: [String] = []
        for a in all where a.kind == .command {
            let c = (a.command ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !c.isEmpty, seen.insert(c).inserted { out.append(c) }
        }
        return out
    }

    // MARK: Plan

    public func plan(_ action: HeraldAction, origin: HeraldActionOrigin,
                     invocation inv: ActionInvocation) -> Result<ActionPlan, ActionError> {
        switch action.kind {
        case .url: return planURL(action, origin: origin, inv)
        case .callback: return .success(.callback(callbackWithExtra(action.callback ?? HeraldCallback(), extra: inv.extra)))
        case .command: return planCommand(action, origin: origin, inv)
        case .script: return planScript(action, origin: origin, inv)
        case .shortcut: return planShortcut(action, inv)
        case .dismiss: return .success(.dismiss)
        case .openApp: return planOpenApp(action)
        case .reply: return .success(.reply(action.reply ?? HeraldReply()))
        case .snooze:
            let minutes = Double(action.snoozeMinutes ?? HeraldAction.defaultSnoozeMinutes)
            guard Snooze.isValid(minutes: minutes) else { return .failure(ActionError("invalid snooze time")) }
            return .success(.snooze(minutes: minutes))
        }
    }

    private func planURL(_ a: HeraldAction, origin: HeraldActionOrigin, _ inv: ActionInvocation) -> Result<ActionPlan, ActionError> {
        guard var text = a.url?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return .failure(ActionError("no link"))
        }
        // `{token}` placeholders belong to the template's own URLs. A link the issuer sent is used as written.
        if origin == .template { text = Self.fillURL(text, fields: inv.fields) }
        guard let url = URL(string: text) else { return .failure(ActionError("invalid link")) }
        guard LinkPolicy.isOpenable(url) else { return .failure(ActionError("this link type is not allowed")) }
        return .success(.openURL(url))
    }

    /// The callback keeps the issuer's own payload. The template's `extra` values are added under `extra` when
    /// the payload is an object (or absent) and does not use that key itself.
    private func callbackWithExtra(_ cb: HeraldCallback, extra: [String: String]) -> HeraldCallback {
        guard !extra.isEmpty else { return cb }
        var out = cb
        let added = JSONValue.object(extra.mapValues { .string($0) })
        switch cb.payload {
        case nil, .null?: out.payload = .object(["extra": added])
        case .object(var o)?:
            if o["extra"] == nil { o["extra"] = added; out.payload = .object(o) }
        default: break
        }
        return out
    }

    private func planCommand(_ a: HeraldAction, origin: HeraldActionOrigin, _ inv: ActionInvocation) -> Result<ActionPlan, ActionError> {
        guard let command = a.command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(ActionError("no command"))
        }
        // The command is never interpolated: tokens, fields and extra values reach it as data (stdin and HERALD_*).
        return .success(.process(ActionProcessSpec(
            kind: .command, executable: shell, arguments: shellArguments + [command],
            stdin: inv.payloadJSON(action: a), environment: Self.environment(a, origin: origin, inv),
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            display: command, timeout: timeout)))
    }

    private func planScript(_ a: HeraldAction, origin: HeraldActionOrigin, _ inv: ActionInvocation) -> Result<ActionPlan, ActionError> {
        let file: URL
        switch resolveScript(a.script) {
        case .failure(let e): return .failure(e)
        case .success(let f): file = f
        }
        let ext = file.pathExtension.lowercased()
        let executable: String
        var arguments: [String]
        if Self.alwaysInterpreted.contains(ext), let i = Self.interpreter(forExtension: ext) {
            executable = i.path; arguments = i.arguments
        } else if FileManager.default.isExecutableFile(atPath: file.path) {
            executable = file.path; arguments = []
        } else if let i = Self.interpreter(forExtension: ext) {
            executable = i.path; arguments = i.arguments
        } else {
            return .failure(ActionError("script is not executable (chmod +x, or use .sh, .py, .scpt)"))
        }
        if executable != file.path { arguments.append(file.path) }
        return .success(.process(ActionProcessSpec(
            kind: .script, executable: executable, arguments: arguments,
            stdin: inv.payloadJSON(action: a), environment: Self.environment(a, origin: origin, inv),
            workingDirectory: scriptsDirectory,
            display: ([executable] + arguments).joined(separator: " "), timeout: timeout)))
    }

    /// An application to bring to the front: the action's own `bundleId` / `path` (checked for shape), else nothing,
    /// which the controller reads as "the issuing application".
    private func planOpenApp(_ a: HeraldAction) -> Result<ActionPlan, ActionError> {
        let bundle = a.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let path = a.path?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let bundle, !HeraldManifest.isBundleId(bundle) { return .failure(ActionError("invalid bundle id")) }
        if let path, !path.lowercased().hasSuffix(".app") { return .failure(ActionError("path is not an application")) }
        return .success(.openApp(bundleId: bundle, path: path))
    }

    private func planShortcut(_ a: HeraldAction, _ inv: ActionInvocation) -> Result<ActionPlan, ActionError> {
        let name = (a.shortcut ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(ActionError("no shortcut name")) }
        // A name that starts with "-" would be read as an option by the shortcuts tool.
        guard !name.hasPrefix("-"), name.utf8.count <= 512,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return .failure(ActionError("invalid shortcut name")) }
        let input: Data, ext: String
        if let text = ActionResolver.inputText(for: a, fields: inv.fields) {
            input = Data(text.utf8); ext = "txt"
        } else {
            input = inv.payloadJSON(action: a); ext = "json"
        }
        return .success(.process(ActionProcessSpec(
            kind: .shortcut, executable: shortcutsPath,
            arguments: ["run", name, "--input-path", ActionProcessSpec.inputPathToken],
            inputFile: input, inputFileExtension: ext,
            workingDirectory: FileManager.default.temporaryDirectory,
            display: "shortcuts run \"\(name)\" --input-path <input.\(ext)>", timeout: timeout)))
    }

    // MARK: Scripts

    /// Extensions that are always run through their interpreter, even with the executable bit set (compiled
    /// AppleScript is not something the kernel can exec).
    private static let alwaysInterpreted: Set<String> = ["applescript", "scpt"]

    static func interpreter(forExtension ext: String) -> (path: String, arguments: [String])? {
        switch ext.lowercased() {
        case "sh", "zsh": return ("/bin/zsh", [])
        case "bash": return ("/bin/bash", [])
        case "py": return ("/usr/bin/python3", [])
        case "rb": return ("/usr/bin/ruby", [])
        case "pl": return ("/usr/bin/perl", [])
        case "applescript", "scpt": return ("/usr/bin/osascript", [])
        default: return nil
        }
    }

    /// A script is a plain file name in the scripts folder (`HeraldScriptName.isPlain`, the rule template validation
    /// uses too): no path separator, no `..`, no absolute path or `~`. (A symlink the user put inside the folder is
    /// theirs to follow.)
    func resolveScript(_ name: String?) -> Result<URL, ActionError> {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return .failure(ActionError("no script name")) }
        guard HeraldScriptName.isPlain(n) else { return .failure(ActionError("script must be a file inside the scripts folder")) }
        let url = scriptsDirectory.appendingPathComponent(n)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return .failure(ActionError("script not found: \(n)"))
        }
        return .success(url)
    }

    public struct ScriptEntry: Equatable, Sendable, Identifiable {
        /// Path relative to the scripts folder.
        public var name: String
        public var isExecutable: Bool
        /// The interpreter used when the file is not executable; nil when there is none for its extension.
        public var interpreter: String?
        public var id: String { name }
        /// Can an action run it?
        public var runnable: Bool { isExecutable || interpreter != nil }
    }

    /// The files directly in the scripts folder (hidden files skipped; sub-folders are not scripts), sorted, at most `limit`.
    public func listScripts(limit: Int = 200) -> [ScriptEntry] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: scriptsDirectory, includingPropertiesForKeys: [.isRegularFileKey],
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]) else { return [] }
        let base = scriptsDirectory.standardizedFileURL.path + "/"
        var out: [ScriptEntry] = []
        for case let url as URL in e {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            let name = path.hasPrefix(base) ? String(path.dropFirst(base.count)) : url.lastPathComponent
            out.append(ScriptEntry(name: name, isExecutable: fm.isExecutableFile(atPath: url.path),
                                   interpreter: Self.interpreter(forExtension: url.pathExtension)?.path))
            if out.count >= limit { break }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Environment

    /// HERALD_APP, HERALD_NOTIFICATION_ID, HERALD_ACTION (the label), HERALD_ACTION_ID, HERALD_ACTION_KIND,
    /// HERALD_ORIGIN, HERALD_TEMPLATE, then HERALD_FIELD_<NAME> for each field and HERALD_EXTRA_<KEY> for each
    /// template `extra` value. Bounded: 100 variables, 4 KB each.
    static func environment(_ a: HeraldAction, origin: HeraldActionOrigin, _ inv: ActionInvocation) -> [String: String] {
        func clean(_ s: String) -> String {
            let noNul = s.replacingOccurrences(of: "\0", with: "")
            return noNul.utf8.count > 4096 ? String(decoding: Array(noNul.utf8.prefix(4096)), as: UTF8.self) : noNul
        }
        func name(_ s: String) -> String {
            String(s.uppercased().unicodeScalars.map { ($0.isASCII && (CharacterSet.alphanumerics.contains($0))) ? Character($0) : "_" })
        }
        var env: [String: String] = [
            "HERALD_APP": clean(inv.notification.app),
            "HERALD_NOTIFICATION_ID": clean(inv.notification.id ?? ""),
            "HERALD_ACTION": clean(a.label), "HERALD_ACTION_ID": clean(a.id),
            "HERALD_ACTION_KIND": a.kind.rawValue, "HERALD_ORIGIN": origin.rawValue,
        ]
        if let t = inv.template, !t.isEmpty { env["HERALD_TEMPLATE"] = clean(t) }
        if let u = inv.unattendedSeconds { env["HERALD_FOLLOW_UP"] = "1"; env["HERALD_UNATTENDED_SECONDS"] = String(u) }
        var extras = 0
        for key in inv.fields.keys.sorted() where extras < 100 {
            guard let v = inv.fields[key], !key.hasPrefix("herald.") else { continue }
            if key.hasPrefix("extra.") { env["HERALD_EXTRA_" + name(String(key.dropFirst(6)))] = clean(TemplateResolver.string(for: v)) }
            else { env["HERALD_FIELD_" + name(key)] = clean(TemplateResolver.string(for: v)) }
            extras += 1
        }
        for (k, v) in inv.extra.sorted(by: { $0.key < $1.key }) where !k.isEmpty { env["HERALD_EXTRA_" + name(k)] = clean(v) }
        return env
    }

    // MARK: URL placeholders

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Fills `{token}` in a template URL in one pass (a value that contains `{x}` is not scanned again). A value
    /// is percent-encoded so it cannot add query parameters or end a path segment, except a token at the very
    /// start whose value is itself an openable link (`{url}`), which is kept whole.
    static func fillURL(_ text: String, fields: [String: HeraldFieldValue]) -> String {
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch == "{", let close = text[i...].firstIndex(of: "}") {
                let name = text[text.index(after: i)..<close]
                if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" }) {
                    let value = fields[String(name)].map { TemplateResolver.string(for: $0) } ?? ""
                    if i == text.startIndex, let u = URL(string: value), LinkPolicy.isOpenable(u) {
                        out += value
                    } else {
                        out += value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
                    }
                    i = text.index(after: close)
                    continue
                }
            }
            out.append(ch)
            i = text.index(after: i)
        }
        return out
    }

    // MARK: Run

    /// Runs a process plan: writes the temporary files, launches, removes them, appends the outcome to the log
    /// and returns it. Never throws: every failure is a result.
    public func run(_ spec: ActionProcessSpec, context: CommandContext, origin: HeraldActionOrigin? = nil) async -> CommandResult {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("herald-action-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }

        var stdinFile: URL?
        var arguments = spec.arguments
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if let data = spec.stdin {
                let u = work.appendingPathComponent("payload.json")
                try data.write(to: u)
                stdinFile = u
            }
            if let data = spec.inputFile {
                let u = work.appendingPathComponent("input." + (spec.inputFileExtension.isEmpty ? "txt" : spec.inputFileExtension))
                try data.write(to: u)
                arguments = arguments.map { $0 == ActionProcessSpec.inputPathToken ? u.path : $0 }
            }
        } catch {
            let r = CommandResult(exitCode: -1, signaled: false, timedOut: false,
                                  launchError: "cannot create temporary files: \(error.localizedDescription)",
                                  output: "", truncated: false, duration: 0)
            log.append(ActionLog.entry(display: spec.display, kind: spec.kind.rawValue, origin: origin, context: context, result: r))
            return r
        }

        let request = ActionProcessRequest(
            executable: spec.executable, arguments: arguments, environment: spec.environment, stdinFile: stdinFile,
            workingDirectory: spec.workingDirectory ?? fm.homeDirectoryForCurrentUser,
            timeout: spec.timeout, outputLimit: outputLimit)
        let result = await launcher.launch(request)
        log.append(ActionLog.entry(display: spec.display, kind: spec.kind.rawValue, origin: origin, context: context, result: result))
        return result
    }

    /// The banner's "Action failed" detail: why it failed, with the program's first line of output when it
    /// said something (`shortcuts` explains a missing Shortcut there).
    public func failureReason(_ r: CommandResult) -> String {
        if let e = r.launchError { return "could not start: \(e)" }
        if r.timedOut { return "timed out after \(Int(timeout)) s" }
        if r.signaled { return "killed by signal \(r.exitCode)" }
        let line = r.output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return line.isEmpty ? "exit \(r.exitCode)" : "exit \(r.exitCode): \(line)"
    }
}

// MARK: - Per-template command confirmation

/// One template whose commands the user agreed to.
public struct TemplateCommandApproval: Codable, Equatable, Sendable, Identifiable {
    public var app: String
    public var template: String
    /// The exact commands that were on the screen when the user agreed.
    public var commands: [String]
    public var approvedAt: Date
    public var id: String { app + "/" + template }

    public init(app: String, template: String, commands: [String], approvedAt: Date = Date()) {
        self.app = app; self.template = template; self.commands = commands; self.approvedAt = approvedAt
    }
}

/// Which template commands the user has confirmed (Application Support/Herald/template-approvals.json).
///
/// The approval is for the commands as they were: a command that is edited, or added later, is not covered
/// and is asked about again. Otherwise anything allowed to save a template could swap an approved command
/// for another one.
public final class TemplateCommandApprovals: @unchecked Sendable {
    private let file: URL
    private let lock = NSLock()
    private var entries: [String: TemplateCommandApproval]

    public init(file: URL) {
        self.file = file
        entries = [:]
        if let data = try? Data(contentsOf: file),
           let list = try? HeraldJSON.decoder().decode([TemplateCommandApproval].self, from: data) {
            for a in list { entries[a.id] = a }
        }
    }

    public func isApproved(app: String, template: String, command: String) -> Bool {
        let c = command.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock(); defer { lock.unlock() }
        return entries[app + "/" + template]?.commands.contains(c) ?? false
    }

    /// Records that `commands` of the template were shown and agreed to (replaces any earlier approval).
    public func approve(app: String, template: String, commands: [String], at date: Date = Date()) {
        let list = commands.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        lock.lock(); defer { lock.unlock() }
        let a = TemplateCommandApproval(app: app, template: template, commands: list, approvedAt: date)
        entries[a.id] = a
        persist()
    }

    public func revoke(app: String, template: String) {
        lock.lock(); defer { lock.unlock() }
        guard entries.removeValue(forKey: app + "/" + template) != nil else { return }
        persist()
    }

    /// Approvals, sorted by app and template.
    public func all() -> [TemplateCommandApproval] {
        lock.lock(); defer { lock.unlock() }
        return entries.values.sorted { ($0.app, $0.template) < ($1.app, $1.template) }
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let list = entries.values.sorted { ($0.app, $0.template) < ($1.app, $1.template) }
        if let data = try? HeraldJSON.encoder().encode(list) { try? data.write(to: file, options: .atomic) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
