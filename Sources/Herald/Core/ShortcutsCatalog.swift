import Foundation

/// The outcome of running a helper program once.
public struct ShortcutsProcessResult: Equatable, Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool
    /// Set when the program could not be started at all (missing, not executable).
    public var launchError: String?

    public init(status: Int32 = 0, stdout: String = "", stderr: String = "", timedOut: Bool = false, launchError: String? = nil) {
        self.status = status; self.stdout = stdout; self.stderr = stderr
        self.timedOut = timedOut; self.launchError = launchError
    }
}

public enum ShortcutsError: Error, Equatable, LocalizedError, Sendable {
    /// `shortcuts` is missing or could not be launched.
    case unavailable(String)
    case timedOut(TimeInterval)
    case failed(status: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let why): return "the shortcuts tool is unavailable: \(why)"
        case .timedOut(let t): return "shortcuts list did not answer within \(Int(t)) s"
        case .failed(let status, let message):
            return "shortcuts list failed (exit \(status))" + (message.isEmpty ? "" : ": \(message)")
        }
    }
}

/// The names of the user's installed Shortcuts, from `/usr/bin/shortcuts list` (the designer's "Run
/// shortcut..." picker and `GET /v1/shortcuts`).
///
/// Asking the Shortcuts database can be slow or even hang (first use after login, an iCloud sync), so the
/// call has a hard timeout, the answer is cached for 30 s and concurrent callers share one process.
public actor ShortcutsCatalog {
    public static let shared = ShortcutsCatalog()

    public static let defaultExecutable = "/usr/bin/shortcuts"
    public static let defaultTimeout: TimeInterval = 5
    public static let defaultCacheTTL: TimeInterval = 30

    /// Runs `executable arguments` and reports how it ended. Injectable so tests need no real Shortcuts.
    public typealias Runner = @Sendable (_ executable: String, _ arguments: [String], _ timeout: TimeInterval) async -> ShortcutsProcessResult

    private let executable: String
    private let arguments: [String]
    private let timeout: TimeInterval
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private let runner: Runner
    private var cached: (names: [String], at: Date)?
    private var inflight: Task<[String], Error>?

    public init(executable: String = ShortcutsCatalog.defaultExecutable,
                arguments: [String] = ["list"],
                timeout: TimeInterval = ShortcutsCatalog.defaultTimeout,
                cacheTTL: TimeInterval = ShortcutsCatalog.defaultCacheTTL,
                now: @escaping @Sendable () -> Date = { Date() },
                runner: @escaping Runner = ShortcutsCatalog.runProcess) {
        self.executable = executable; self.arguments = arguments; self.timeout = timeout
        self.ttl = cacheTTL; self.now = now; self.runner = runner
    }

    /// Installed shortcut names, sorted. Served from the cache for 30 s unless `refresh` is true. Failures
    /// are never cached, so the next call tries again.
    public func names(refresh: Bool = false) async throws -> [String] {
        if !refresh, let c = cached, now().timeIntervalSince(c.at) < ttl { return c.names }
        if let running = inflight { return try await running.value }

        let (executable, arguments, timeout, runner) = (self.executable, self.arguments, self.timeout, self.runner)
        let task = Task<[String], Error> {
            let r = await runner(executable, arguments, timeout)
            if let e = r.launchError { throw ShortcutsError.unavailable(e) }
            if r.timedOut { throw ShortcutsError.timedOut(timeout) }
            guard r.status == 0 else {
                throw ShortcutsError.failed(status: r.status, message: Self.firstLine(r.stderr))
            }
            return Self.parse(r.stdout)
        }
        inflight = task
        defer { inflight = nil }
        let names = try await task.value
        cached = (names, now())
        return names
    }

    /// Forgets the cached list (the next `names()` runs the program again).
    public func invalidate() { cached = nil }

    // MARK: Parsing

    /// One name per line. Blank lines and control characters are dropped, duplicates collapse and the
    /// result is sorted the way the Shortcuts app sorts (case-insensitive, localized).
    public static func parse(_ output: String) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for line in output.components(separatedBy: .newlines) {
            let name = String(String.UnicodeScalarView(line.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.utf8.count <= maxNameBytes, seen.insert(name).inserted else { continue }
            names.append(name)
            if names.count >= maxNames { break }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Bounds on what one `shortcuts list` may contribute (it is user data, shown in a picker and an API).
    static let maxNames = 2000
    static let maxNameBytes = 512

    private static func firstLine(_ s: String) -> String {
        let line = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.count > 200 ? String(line.prefix(200)) + "..." : line
    }

    // MARK: Process

    /// Runs the program with a hard deadline: the answer is `timedOut` at `timeout` whatever the program
    /// is doing, and it is sent SIGTERM then, SIGKILL two seconds later if it is still there. Output is
    /// read while it runs (so a long list cannot fill the pipe and stall the program) and capped at 1 MB
    /// per stream.
    public static let runProcess: Runner = { executable, arguments, timeout in
        await withCheckedContinuation { (continuation: CheckedContinuation<ShortcutsProcessResult, Never>) in
            let run = ProcessRun(continuation)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            // Entered before the program starts: a program that ends at once must not find an empty group.
            let readers = DispatchGroup()
            readers.enter(); readers.enter()
            process.terminationHandler = { p in
                // Both pipes reach end-of-file once the program (and anything it started) has closed them.
                readers.notify(queue: .global()) { run.finish(status: p.terminationStatus, timedOut: false) }
            }
            do {
                try process.run()
            } catch {
                run.finish(status: -1, launchError: error.localizedDescription)
                return
            }
            for (handle, isOut) in [(out.fileHandleForReading, true), (err.fileHandleForReading, false)] {
                DispatchQueue.global().async {
                    while true {
                        let chunk = handle.availableData
                        if chunk.isEmpty { break }
                        run.append(chunk, toStdout: isOut)
                    }
                    readers.leave()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
                run.finish(status: -1, timedOut: true)
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
    }
}

/// Collects a program's output and answers the continuation exactly once, from whichever of "the program
/// ended" and "the deadline passed" happens first.
private final class ProcessRun: @unchecked Sendable {
    private static let cap = 1_000_000
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ShortcutsProcessResult, Never>?
    private var stdout = Data()
    private var stderr = Data()

    init(_ c: CheckedContinuation<ShortcutsProcessResult, Never>) { continuation = c }

    func append(_ chunk: Data, toStdout: Bool) {
        lock.lock(); defer { lock.unlock() }
        if toStdout { if stdout.count < Self.cap { stdout.append(chunk) } }
        else if stderr.count < Self.cap { stderr.append(chunk) }
    }

    func finish(status: Int32, timedOut: Bool = false, launchError: String? = nil) {
        lock.lock()
        guard let c = continuation else { lock.unlock(); return }
        continuation = nil
        let result = ShortcutsProcessResult(
            status: status,
            stdout: String(decoding: stdout.prefix(Self.cap), as: UTF8.self),
            stderr: String(decoding: stderr.prefix(Self.cap), as: UTF8.self),
            timedOut: timedOut, launchError: launchError)
        lock.unlock()
        c.resume(returning: result)
    }
}
