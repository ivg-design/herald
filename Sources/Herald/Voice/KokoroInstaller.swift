import Foundation

/// Downloads Kokoro (optional, ~340 MB), builds its Python environment and shows SHA-256 sums; or links an
/// existing installation such as `~/.claude/tts`. Everything lands in `<support>/tts`.
@MainActor
final class KokoroInstaller: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(file: String, fraction: Double)
        case settingUp(String)
        case done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var checksums: [String: String] = [:]
    @Published private(set) var log: [String] = []
    @Published private(set) var revision = 0   // bumps when the installation on disk changes

    let layout: KokoroLayout
    private var task: Task<Void, Never>?
    private var downloader: ResumableDownloader?
    private var currentProcess: Process?
    /// Bumped by `install()` and `cancel()`. A run that is no longer the current one (it was cancelled while a
    /// download or a tool was unwinding) must not touch the published state any more.
    private var generation = 0

    init(layout: KokoroLayout) { self.layout = layout }

    var isBusy: Bool {
        switch phase { case .downloading, .settingUp: return true; default: return false }
    }

    /// ~/.claude/tts when it is a complete installation.
    var existing: KokoroLayout? { KokoroLayout.existingInstallation() }

    // MARK: Use existing

    func useExisting(_ source: KokoroLayout) {
        do {
            try layout.link(to: source)
            phase = .done
            log.append("Linked \(source.root.path)")
            installationChanged()
        } catch { phase = .failed(error.localizedDescription) }
    }

    // MARK: Download + environment

    func install() {
        guard !isBusy else { return }
        generation += 1
        let gen = generation
        phase = .settingUp("Starting")   // busy at once, so a second press before the task starts is ignored
        task = Task { [weak self] in await self?.run(generation: gen) }
    }

    /// Stops the download or the running tool. A partial download stays on disk as `<file>.part`, and the next
    /// `install()` continues from it.
    func cancel() {
        guard isBusy else { return }
        generation += 1
        downloader?.cancel()
        if let p = currentProcess, p.isRunning { p.terminate() }
        task?.cancel()
        log.append("Cancelled")
        phase = .idle
    }

    private func setPhase(_ p: Phase, _ gen: Int) { if gen == generation { phase = p } }

    private func run(generation gen: Int) async {
        func current() throws { if gen != generation { throw CancellationError() } }
        do {
            try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
            for name in [KokoroLayout.voicesFile, KokoroLayout.modelFile] {
                let dest = layout.root.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    setPhase(.downloading(file: name, fraction: 0), gen)
                    let d = ResumableDownloader()
                    downloader = d
                    try await d.download(URL(string: KokoroLayout.releaseBase + name)!, to: dest) { [weak self] f in
                        Task { @MainActor in self?.setPhase(.downloading(file: name, fraction: f), gen) }
                    }
                    try current()
                }
                setPhase(.settingUp("Checksum \(name)"), gen)
                let sum = try await Task.detached { try KokoroLayout.sha256(of: dest) }.value
                try current()
                checksums[name] = sum
                log.append("\(name) sha256 \(sum)")
            }
            if !layout.hasPython || layout.environmentIncomplete { try await prepareEnvironment(gen) }
            try current()
            setPhase(layout.isInstalled ? .done : .failed("Installation incomplete: \(layout.missing.joined(separator: ", "))"), gen)
            installationChanged()
        } catch {
            guard gen == generation else { return }   // cancelled: `cancel()` already reset the state
            phase = error is CancellationError ? .idle : .failed(error.localizedDescription)
        }
    }

    /// Builds the venv unless a venv Herald left behind earlier already imports cleanly, then marks it ready.
    private func prepareEnvironment(_ gen: Int) async throws {
        if layout.hasPython, (try? await runTool(layout.python.path, ["-c", Self.importCheck])) != nil {
            try? Data().write(to: layout.environmentMarker)
            return
        }
        // A half-built venv (a failed or interrupted pip install) would otherwise count as installed.
        try? FileManager.default.removeItem(at: layout.venv)
        do {
            try await buildEnvironment(gen)
            setPhase(.settingUp("Checking the environment"), gen)
            try await runTool(layout.python.path, ["-c", Self.importCheck])
            try Data().write(to: layout.environmentMarker)
        } catch {
            // Only while this run is still the current one: after a cancel a newer run may already be building.
            if gen == generation { try? FileManager.default.removeItem(at: layout.venv) }
            throw error
        }
    }

    private static let importCheck = "import kokoro_onnx, soundfile"

    private func buildEnvironment(_ gen: Int) async throws {
        let venv = layout.venv.path
        if let uv = Self.find("uv") {
            setPhase(.settingUp("Creating Python 3.12 environment (uv)"), gen)
            try await runTool(uv, ["venv", "--python", "3.12", venv])
            setPhase(.settingUp("Installing kokoro-onnx and soundfile"), gen)
            try await runTool(uv, ["pip", "install", "--python", layout.python.path, "kokoro-onnx", "soundfile"])
        } else if let py = Self.find("python3") {
            setPhase(.settingUp("Creating Python environment"), gen)
            try await runTool(py, ["-m", "venv", venv])
            setPhase(.settingUp("Installing kokoro-onnx and soundfile (pip)"), gen)
            try await runTool(layout.venv.appendingPathComponent("bin/pip").path, ["install", "kokoro-onnx", "soundfile"])
        } else {
            throw TTSWorkerError.notInstalled("neither uv nor python3 was found; install one (brew install uv) and try again")
        }
    }

    /// GUI apps get a minimal PATH, so the usual install locations are searched explicitly.
    static func find(_ tool: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.cargo/bin", "/usr/bin"] {
            let p = dir + "/" + tool
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    @discardableResult
    private func runTool(_ exe: String, _ args: [String]) async throws -> String {
        log.append("$ \((exe as NSString).lastPathComponent) \(args.joined(separator: " "))")
        let p = Process()
        currentProcess = p
        defer { currentProcess = nil }
        let output: (Int32, String) = try await withCheckedThrowingContinuation { cont in
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            p.terminationHandler = { proc in
                let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                cont.resume(returning: (proc.terminationStatus, text))
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
        if let last = output.1.split(separator: "\n").last { log.append(String(last)) }
        if output.0 != 0 { throw TTSWorkerError.failed("\((exe as NSString).lastPathComponent) exited \(output.0): \(output.1.suffix(300))") }
        return output.1
    }

    private func installationChanged() {
        revision += 1
        NotificationCenter.default.post(name: VoiceSettings.engineChanged, object: nil)
    }
}

/// A resumable download: data goes to `<dest>.part` and a restart continues from the bytes already there
/// (`Range: bytes=N-`). The finished file is moved into place. How the server's answer is read is
/// `DownloadResume.decide`.
final class ResumableDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// The `.part` file turned out not to be a prefix of the file on the server.
    private enum PartError: Error { case notAPrefix }

    private var session: URLSession?
    private var handle: FileHandle?
    private var partURL: URL?
    private var expected: Int64 = 0
    private var received: Int64 = 0
    private var progress: ((Double) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    private var dest: URL?

    func download(_ url: URL, to dest: URL, progress: @escaping (Double) -> Void) async throws {
        do { try await attempt(url, to: dest, progress: progress) }
        catch PartError.notAPrefix {
            try? FileManager.default.removeItem(at: dest.appendingPathExtension("part"))
            try await attempt(url, to: dest, progress: progress)
        }
    }

    private func attempt(_ url: URL, to dest: URL, progress: @escaping (Double) -> Void) async throws {
        let part = dest.appendingPathExtension("part")
        let have = ((try? FileManager.default.attributesOfItem(atPath: part.path))?[.size] as? NSNumber)?.int64Value ?? 0
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        if let range = DownloadResume.rangeHeader(have: have) { req.setValue(range, forHTTPHeaderField: "Range") }
        self.dest = dest; self.partURL = part; self.progress = progress; self.received = have
        if !FileManager.default.fileExists(atPath: part.path) { FileManager.default.createFile(atPath: part.path, contents: nil) }
        handle = try FileHandle(forWritingTo: part)
        try handle?.seekToEnd()
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session = s
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            s.dataTask(with: req).resume()
        }
    }

    func cancel() {
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else { completionHandler(.cancel); return }
        switch DownloadResume.decide(status: http.statusCode, have: received, contentLength: http.expectedContentLength,
                                     contentRange: http.value(forHTTPHeaderField: "Content-Range")) {
        case .resume(let total):
            expected = total
        case .restart(let total):
            try? handle?.truncate(atOffset: 0)
            try? handle?.seek(toOffset: 0)
            received = 0
            expected = total
        case .alreadyComplete:
            completionHandler(.cancel)
            finish(nil)
            return
        case .discardPart:
            completionHandler(.cancel)
            finish(PartError.notAPrefix)
            return
        case .fail(let code):
            completionHandler(.cancel)
            finish(TTSWorkerError.failed("download failed (HTTP \(code))"))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        try? handle?.write(contentsOf: data)
        received += Int64(data.count)
        if expected > 0 { progress?(min(1, Double(received) / Double(expected))) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // The 416 paths cancel the task on purpose; they were already finished above.
        guard continuation != nil else { return }
        finish(error)
    }

    private func finish(_ error: Error?) {
        guard let c = continuation else { return }
        continuation = nil
        try? handle?.close(); handle = nil
        session?.finishTasksAndInvalidate()
        if let error { c.resume(throwing: error); return }
        do {
            if let dest, let partURL {
                if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                try FileManager.default.moveItem(at: partURL, to: dest)
            }
            c.resume()
        } catch { c.resume(throwing: error) }
    }
}
