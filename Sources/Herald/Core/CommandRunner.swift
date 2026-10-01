import Foundation

/// May an app's `command` buttons run? Both halves of the gate have to be open: the app asked for it at
/// registration (`allowCommands`) and the user said yes (`commandsConfirmed`, set from Settings or from the
/// first-run alert).
public enum CommandPermission: Equatable, Sendable {
    case allowed
    /// The app asked, the user has not answered yet: show the exact command and ask.
    case needsConfirmation
    case denied(String)

    public static func evaluate(_ record: AppRecord?) -> CommandPermission {
        guard let record, record.registration.allowCommands == true else {
            return .denied("this app has not registered with allowCommands")
        }
        return record.commandsConfirmed ? .allowed : .needsConfirmation
    }
}

public struct CommandContext: Equatable, Sendable {
    public var app: String
    public var notificationId: String
    public var action: String
    public init(app: String, notificationId: String, action: String) {
        self.app = app; self.notificationId = notificationId; self.action = action
    }
}

public struct CommandResult: Equatable, Sendable {
    /// Exit status, or the signal number when the process was killed.
    public var exitCode: Int32
    public var signaled: Bool
    public var timedOut: Bool
    /// Set when the shell could not be started at all.
    public var launchError: String?
    /// Combined stdout and stderr, capped (see `CommandRunner.outputLimit`).
    public var output: String
    public var truncated: Bool
    public var duration: TimeInterval

    public var succeeded: Bool { launchError == nil && !timedOut && !signaled && exitCode == 0 }

    /// One short phrase for the log and the banner.
    public var summary: String {
        if let e = launchError { return "could not start: \(e)" }
        if timedOut { return "timed out" }
        if signaled { return "killed by signal \(exitCode)" }
        return exitCode == 0 ? "exit 0" : "exit \(exitCode)"
    }
}

/// Appends command runs to `~/Library/Logs/Herald/commands.log`. One backup generation is kept so the log
/// cannot grow without bound.
public final class CommandLog: @unchecked Sendable {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Herald/commands.log")
    }

    public let url: URL
    private let maxBytes: Int
    private let lock = NSLock()

    public init(url: URL = CommandLog.defaultURL, maxBytes: Int = 1_000_000) {
        self.url = url; self.maxBytes = maxBytes
    }

    public func append(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size >= maxBytes {
            let backup = url.appendingPathExtension("1")
            try? fm.removeItem(at: backup)
            try? fm.moveItem(at: url, to: backup)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(text.utf8))
    }

    /// The text of one log entry. Pure, so tests can check the format.
    public static func entry(command: String, context: CommandContext, result: CommandResult, at date: Date = Date()) -> String {
        var s = "\(ISODate.string(from: date)) app=\(context.app) id=\(context.notificationId) action=\"\(context.action)\" "
        s += "result=\"\(result.summary)\" duration=\(String(format: "%.2f", result.duration))s\n"
        s += "$ \(command)\n"
        if !result.output.isEmpty {
            s += result.output.hasSuffix("\n") ? result.output : result.output + "\n"
            if result.truncated { s += "[output truncated]\n" }
        }
        s += "---\n"
        return s
    }
}

/// Runs a button's shell command. The user's own login shell environment is what the command expects
/// (`/bin/zsh -lc`: PATH from the profile), so that is what it gets.
public final class CommandRunner: @unchecked Sendable {
    public static let defaultShell = "/bin/zsh"
    public static let defaultShellArguments = ["-lc"]

    public let shell: String
    public let shellArguments: [String]
    /// Seconds before the process is terminated. Commands are button actions ("archive this", "open that"),
    /// not daemons; one that is still running after this long is stuck, and the banner is waiting on it.
    public let timeout: TimeInterval
    public let outputLimit: Int
    public let log: CommandLog

    public init(shell: String = CommandRunner.defaultShell,
                shellArguments: [String] = CommandRunner.defaultShellArguments,
                timeout: TimeInterval = 30, outputLimit: Int = 64 * 1024,
                log: CommandLog = CommandLog()) {
        self.shell = shell; self.shellArguments = shellArguments
        self.timeout = timeout; self.outputLimit = outputLimit; self.log = log
    }

    /// Runs `command`, appends the outcome to the log and returns it. Never throws: every failure is a result.
    public func run(_ command: String, context: CommandContext) async -> CommandResult {
        let result: CommandResult = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: self.runBlocking(command, context)) }
        }
        log.append(CommandLog.entry(command: command, context: context, result: result))
        return result
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    private func runBlocking(_ command: String, _ context: CommandContext) -> CommandResult {
        let started = Date()
        func failed(_ message: String) -> CommandResult {
            CommandResult(exitCode: -1, signaled: false, timedOut: false, launchError: message,
                          output: "", truncated: false, duration: Date().timeIntervalSince(started))
        }

        // Output goes to a temp file, not a pipe: a command that backgrounds something (`foo &`) leaves a
        // child holding a pipe open, and reading the pipe to EOF would then wait for that child for ever.
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("herald-command-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: outURL.path, contents: nil),
              let out = try? FileHandle(forWritingTo: outURL) else { return failed("cannot create an output file") }
        defer { try? out.close(); try? FileManager.default.removeItem(at: outURL) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = shellArguments + [command]
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var env = ProcessInfo.processInfo.environment
        env["HERALD_APP"] = context.app
        env["HERALD_NOTIFICATION_ID"] = context.notificationId
        env["HERALD_ACTION"] = context.action
        p.environment = env
        p.standardInput = FileHandle.nullDevice
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
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        p.waitUntilExit()
        killer.cancel()

        var data = Data()
        var truncated = false
        if let reader = try? FileHandle(forReadingFrom: outURL) {
            data = (try? reader.read(upToCount: outputLimit + 1)) ?? Data()
            try? reader.close()
            if data.count > outputLimit { data = data.prefix(outputLimit); truncated = true }
        }
        return CommandResult(exitCode: p.terminationStatus, signaled: p.terminationReason == .uncaughtSignal,
                             timedOut: timedOut.isSet, launchError: nil,
                             output: String(decoding: data, as: UTF8.self), truncated: truncated,
                             duration: Date().timeIntervalSince(started))
    }
}
