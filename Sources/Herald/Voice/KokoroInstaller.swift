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
        task = Task { [weak self] in await self?.run() }
    }

    func cancel() {
        downloader?.cancel()
        task?.cancel()
        phase = .idle
    }

    private func run() async {
        do {
            try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
            for name in [KokoroLayout.voicesFile, KokoroLayout.modelFile] {
                let dest = layout.root.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    phase = .downloading(file: name, fraction: 0)
                    let d = ResumableDownloader()
                    downloader = d
                    try await d.download(URL(string: KokoroLayout.releaseBase + name)!, to: dest) { [weak self] f in
                        Task { @MainActor in self?.phase = .downloading(file: name, fraction: f) }
                    }
                }
                phase = .settingUp("Checksum \(name)")
                let sum = try await Task.detached { try KokoroLayout.sha256(of: dest) }.value
                checksums[name] = sum
                log.append("\(name) sha256 \(sum)")
            }
            if !layout.hasPython { try await buildEnvironment() }
            phase = layout.isInstalled ? .done : .failed("Installation incomplete: \(layout.missing.joined(separator: ", "))")
            installationChanged()
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func buildEnvironment() async throws {
        let venv = layout.venv.path
        if let uv = Self.find("uv") {
            phase = .settingUp("Creating Python 3.12 environment (uv)")
            try await runTool(uv, ["venv", "--python", "3.12", venv])
            phase = .settingUp("Installing kokoro-onnx and soundfile")
            try await runTool(uv, ["pip", "install", "--python", layout.python.path, "kokoro-onnx", "soundfile"])
        } else if let py = Self.find("python3") {
            phase = .settingUp("Creating Python environment")
            try await runTool(py, ["-m", "venv", venv])
            phase = .settingUp("Installing kokoro-onnx and soundfile (pip)")
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

    private func runTool(_ exe: String, _ args: [String]) async throws {
        log.append("$ \((exe as NSString).lastPathComponent) \(args.joined(separator: " "))")
        let output: (Int32, String) = try await withCheckedThrowingContinuation { cont in
            let p = Process()
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
    }

    private func installationChanged() {
        revision += 1
        NotificationCenter.default.post(name: VoiceSettings.engineChanged, object: nil)
    }
}

/// A resumable download: data goes to `<dest>.part` and a restart continues from the bytes already there
/// (`Range: bytes=N-`). The finished file is moved into place.
final class ResumableDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var session: URLSession?
    private var handle: FileHandle?
    private var partURL: URL?
    private var expected: Int64 = 0
    private var received: Int64 = 0
    private var progress: ((Double) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    private var dest: URL?

    func download(_ url: URL, to dest: URL, progress: @escaping (Double) -> Void) async throws {
        let part = dest.appendingPathExtension("part")
        let have = ((try? FileManager.default.attributesOfItem(atPath: part.path))?[.size] as? NSNumber)?.int64Value ?? 0
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        if have > 0 { req.setValue("bytes=\(have)-", forHTTPHeaderField: "Range") }
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
        switch http.statusCode {
        case 206:
            expected = received + http.expectedContentLength
        case 200:
            // The server ignored the range (or there was nothing to resume): start over.
            try? handle?.truncate(atOffset: 0)
            try? handle?.seek(toOffset: 0)
            received = 0
            expected = http.expectedContentLength
        case 416:
            // The part file is already complete.
            completionHandler(.cancel)
            finish(nil)
            return
        default:
            completionHandler(.cancel)
            finish(TTSWorkerError.failed("download failed (HTTP \(http.statusCode))"))
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
        // The 416 path cancels the task on purpose; it was already finished above.
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
