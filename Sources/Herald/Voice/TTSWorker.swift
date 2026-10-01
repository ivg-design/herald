import Foundation

// The Python side is Resources/tts_worker.py. The protocol is one JSON object per line on stdin and one per line
// on stdout. Nothing is ever interpolated into a command line: the text only travels as a JSON string.

public struct TTSRequest: Codable, Equatable, Sendable {
    /// Nil for a synthesis request, "voices" to list the model's voices.
    public var cmd: String?
    public var text: String?
    public var voice: String?
    public var speed: Double?
    public var lang: String?
    /// Absolute path of the WAV the worker writes.
    public var out: String?
    public init(cmd: String? = nil, text: String? = nil, voice: String? = nil, speed: Double? = nil,
                lang: String? = nil, out: String? = nil) {
        self.cmd = cmd; self.text = text; self.voice = voice; self.speed = speed; self.lang = lang; self.out = out
    }
}

public struct TTSResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var out: String?
    public var duration: Double?
    public var error: String?
    public var voices: [String]?
    public init(ok: Bool, out: String? = nil, duration: Double? = nil, error: String? = nil, voices: [String]? = nil) {
        self.ok = ok; self.out = out; self.duration = duration; self.error = error; self.voices = voices
    }
}

public enum TTSWorkerError: Error, Equatable, LocalizedError {
    case notInstalled(String)
    case workerExited
    case timedOut
    case badResponse(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let why): return "Kokoro is not installed: \(why)"
        case .workerExited: return "The speech worker exited unexpectedly"
        case .timedOut: return "The speech worker did not answer in time"
        case .badResponse(let line): return "Unreadable answer from the speech worker: \(line.prefix(120))"
        case .failed(let why): return "Speech synthesis failed: \(why)"
        }
    }
}

public enum TTSWorkerProtocol {
    /// One request as a single line (no embedded newline: JSON escapes them) ending in "\n".
    public static func encode(_ request: TTSRequest) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var d = try enc.encode(request)
        d.append(0x0A)
        return d
    }

    public static func parse(line: String) throws -> TTSResponse {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let r = try? JSONDecoder().decode(TTSResponse.self, from: data) else {
            throw TTSWorkerError.badResponse(trimmed)
        }
        return r
    }
}

/// A running worker process, as the `TTSWorker` sees it. The real one wraps `Process`; tests supply a fake.
public protocol TTSProcess: AnyObject, Sendable {
    /// Called once per stdout line, and once when the process ends.
    func start(onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable () -> Void) throws
    func send(_ data: Data)
    func terminate()
}

/// Keeps one worker process alive, feeds it one request at a time and restarts it after a crash.
/// A request that was in flight when the process died is retried once on a fresh process.
public actor TTSWorker {
    public typealias Factory = @Sendable () throws -> TTSProcess

    private let factory: Factory
    private let requestTimeout: TimeInterval
    private var process: TTSProcess?
    private var generation = 0
    private var pending: CheckedContinuation<TTSResponse, Error>?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Number of processes started so far (tests assert the restart).
    public private(set) var launches = 0

    public init(requestTimeout: TimeInterval = 180, factory: @escaping Factory) {
        self.factory = factory; self.requestTimeout = requestTimeout
    }

    public func request(_ r: TTSRequest) async throws -> TTSResponse {
        await acquire()
        defer { release() }
        do { return try await roundTrip(r) }
        catch TTSWorkerError.workerExited { return try await roundTrip(r) }
    }

    public func voices() async throws -> [String] {
        let r = try await request(TTSRequest(cmd: "voices"))
        guard r.ok else { throw TTSWorkerError.failed(r.error ?? "unknown") }
        return r.voices ?? []
    }

    /// Synthesizes `text` into `out`. Returns the duration in seconds.
    public func synthesize(text: String, voice: String, speed: Double, lang: String, out: URL) async throws -> Double {
        let r = try await request(TTSRequest(text: text, voice: voice, speed: speed, lang: lang, out: out.path))
        guard r.ok else { throw TTSWorkerError.failed(r.error ?? "unknown") }
        return r.duration ?? 0
    }

    public func shutdown() {
        generation += 1
        process?.terminate(); process = nil
        pending?.resume(throwing: TTSWorkerError.workerExited); pending = nil
    }

    // MARK: Internals

    private func acquire() async {
        if busy { await withCheckedContinuation { waiters.append($0) } } else { busy = true }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    private func ensureProcess() throws -> TTSProcess {
        if let process { return process }
        let p = try factory()
        generation += 1
        let gen = generation
        launches += 1
        try p.start(
            onLine: { [weak self] line in Task { await self?.received(line, generation: gen) } },
            onExit: { [weak self] in Task { await self?.exited(generation: gen) } })
        process = p
        return p
    }

    private func roundTrip(_ r: TTSRequest) async throws -> TTSResponse {
        let p = try ensureProcess()
        let gen = generation
        let data = try TTSWorkerProtocol.encode(r)
        let timeout = requestTimeout
        let timer = Task { [weak self] in
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await self?.timedOut(generation: gen)
        }
        defer { timer.cancel() }
        return try await withCheckedThrowingContinuation { cont in
            pending = cont
            p.send(data)
        }
    }

    private func received(_ line: String, generation gen: Int) {
        guard gen == generation, let cont = pending else { return }
        pending = nil
        do { cont.resume(returning: try TTSWorkerProtocol.parse(line: line)) }
        catch { cont.resume(throwing: error) }
    }

    private func exited(generation gen: Int) {
        guard gen == generation else { return }
        process = nil
        generation += 1
        pending?.resume(throwing: TTSWorkerError.workerExited); pending = nil
    }

    private func timedOut(generation gen: Int) {
        guard gen == generation, pending != nil else { return }
        let p = process
        process = nil
        generation += 1
        p?.terminate()
        pending?.resume(throwing: TTSWorkerError.timedOut); pending = nil
    }
}

/// The real worker process: `python tts_worker.py <model> <voices>`, cwd = the Kokoro directory.
public final class PythonTTSProcess: TTSProcess, @unchecked Sendable {
    private let python: URL
    private let script: URL
    private let directory: URL
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var buffer = Data()

    public init(python: URL, script: URL, directory: URL) {
        self.python = python; self.script = script; self.directory = directory
    }

    public func start(onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable () -> Void) throws {
        signal(SIGPIPE, SIG_IGN)   // a worker that died between requests must not take Herald down on write
        process.executableURL = python
        process.arguments = [script.path, directory.appendingPathComponent("kokoro-v1.0.onnx").path,
                             directory.appendingPathComponent("voices-v1.0.bin").path]
        process.currentDirectoryURL = directory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        process.environment = env
        output.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard let self else { return }
            if chunk.isEmpty { h.readabilityHandler = nil; return }
            self.lock.lock()
            self.buffer.append(chunk)
            var lines: [String] = []
            while let nl = self.buffer.firstIndex(of: 0x0A) {
                lines.append(String(decoding: self.buffer[self.buffer.startIndex..<nl], as: UTF8.self))
                self.buffer.removeSubrange(self.buffer.startIndex...nl)
            }
            self.lock.unlock()
            lines.forEach(onLine)
        }
        process.terminationHandler = { _ in onExit() }
        try process.run()
    }

    public func send(_ data: Data) {
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    public func terminate() {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}
