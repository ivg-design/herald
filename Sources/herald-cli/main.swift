import Foundation
import HeraldClient

// Thin driver: all parsing lives in HeraldClient/CLIArguments.swift.

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

// HERALD_SUPPORT_DIR points the tool at a development Herald's data, like the app itself.
let supportDir = HeraldPaths.defaultSupportDirectory

func readTrimmed(_ name: String) -> String? {
    guard let s = try? String(contentsOf: supportDir.appendingPathComponent(name), encoding: .utf8) else { return nil }
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

let invocation: CLIInvocation
do {
    invocation = try CLIArguments.parse(Array(CommandLine.arguments.dropFirst())) { source in
        source == "-" ? FileHandle.standardInput.readDataToEndOfFile()
                      : try Data(contentsOf: URL(fileURLWithPath: (source as NSString).expandingTildeInPath))
    }
} catch let e as CLIParseError {
    fail("herald: \(e.message)\nTry 'herald --help'.")
} catch {
    fail("herald: \(error)")
}

switch invocation.action {
case .help:
    print(CLIArguments.usage)
    exit(0)
case .version:
    print("herald 1.1.0")
    exit(0)
case .request(let req):
    let target = resolveTarget()
    let (status, data) = send(req, to: target)
    var text = String(data: data, encoding: .utf8) ?? ""
    if let obj = try? JSONSerialization.jsonObject(with: data),
       let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let s = String(data: pretty, encoding: .utf8) { text = s }
    if (200..<300).contains(status) {
        if !text.isEmpty { print(text) }
        exit(0)
    }
    if !text.isEmpty { print(text) }
    if status == 401 { FileHandle.standardError.write(Data("herald: unauthorized (check the token file or --token)\n".utf8)) }
    exit(1)
case .templateExport(let e):
    exportTemplate(e, target: resolveTarget())
case .templateImport(let i):
    importTemplate(i, target: resolveTarget())
}

// MARK: - Requests

struct Target { var port: Int; var token: String? }

func resolveTarget() -> Target {
    Target(port: invocation.port ?? readTrimmed("port").flatMap(Int.init) ?? CLIArguments.defaultPort,
           token: invocation.token ?? readTrimmed("token"))
}

/// One request to the running Herald; exits with the usual messages when it is not running.
func send(_ req: CLIRequest, to target: Target) -> (status: Int, data: Data) {
    var comps = URLComponents()
    comps.scheme = "http"; comps.host = "127.0.0.1"; comps.port = target.port; comps.path = req.path
    if !req.query.isEmpty { comps.queryItems = req.query.map { URLQueryItem(name: $0.name, value: $0.value) } }
    guard let url = comps.url else { fail("herald: could not build request URL") }

    var request = URLRequest(url: url, timeoutInterval: 15)
    request.httpMethod = req.method
    if req.needsAuth, let token = target.token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body = req.body {
        do { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        catch { fail("herald: payload is not valid JSON: \(error.localizedDescription)") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return perform(request)
}

func perform(_ request: URLRequest) -> (status: Int, data: Data) {
    let sem = DispatchSemaphore(value: 0)
    var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
    URLSession(configuration: .ephemeral).dataTask(with: request) { d, r, e in
        result = (d, r, e); sem.signal()
    }.resume()
    sem.wait()

    if let error = result.2 {
        let code = (error as? URLError)?.code
        let notRunning: [URLError.Code] = [.cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .timedOut]
        if let code, notRunning.contains(code) { fail(CLIArguments.notRunningMessage, code: 2) }
        fail("herald: \(error.localizedDescription)")
    }
    return ((result.1 as? HTTPURLResponse)?.statusCode ?? 0, result.0 ?? Data())
}

// MARK: - Template bundles (the format and the file work are HeraldTemplateBundle's)

/// Every saved template of an app, from the running Herald.
func templates(of app: String, target: Target) -> [HeraldTemplate] {
    struct Reply: Decodable { var items: [HeraldTemplate] }
    let (status, data) = send(CLIRequest(method: "GET", path: "/v1/templates", query: [("app", app)]), to: target)
    if status == 401 { fail("herald: unauthorized (check the token file or --token)") }
    guard (200..<300).contains(status), let reply = try? HeraldJSON.decoder().decode(Reply.self, from: data) else {
        fail("herald: could not read the templates of \(app) (HTTP \(status))")
    }
    return reply.items
}

func exportTemplate(_ e: CLITemplateExport, target: Target) -> Never {
    guard let template = templates(of: e.app, target: target).first(where: { $0.name == e.name }) else {
        fail("herald: no template \u{201C}\(e.name)\u{201D} for \(e.app)")
    }
    let (status, data) = send(CLIRequest(method: "GET", path: "/v1/manifest", query: [("app", e.app)]), to: target)
    let manifest = status == 200 ? try? HeraldJSON.decoder().decode(HeraldManifest.self, from: data) : nil
    let destination = e.output ?? "\(HeraldTemplateBundle.sanitizedTemplateName(e.name)).\(HeraldTemplateBundle.fileExtension)"
    let url = URL(fileURLWithPath: (destination as NSString).expandingTildeInPath)
    do {
        let out = try HeraldTemplateBundle.export(
            template, locate: HeraldTemplateBundle.locator(app: e.app, supportDirectory: supportDir, manifest: manifest))
        try out.data.write(to: url, options: .atomic)
        for w in out.warnings { FileHandle.standardError.write(Data("herald: \(w)\n".utf8)) }
        print("Wrote \(url.path) (\(out.assetFiles.count) animation file\(out.assetFiles.count == 1 ? "" : "s"))")
        exit(0)
    } catch {
        fail("herald: \(error.localizedDescription)")
    }
}

func importTemplate(_ i: CLITemplateImport, target: Target) -> Never {
    do {
        let source = URL(fileURLWithPath: (i.file as NSString).expandingTildeInPath)
        guard let bytes = try? Data(contentsOf: source) else { fail("herald: cannot read \(source.path)") }
        var contents = try HeraldTemplateBundle.unpack(bytes)
        let app = i.app ?? contents.template.app
        contents.template.app = app

        let taken = Set(templates(of: app, target: target).map(\.name))
        let bundled = contents.template.name
        var name = bundled
        if taken.contains(name) {
            switch i.conflict {
            case .keepBoth: name = HeraldTemplateBundle.uniqueName(bundled, taken: taken)
            case .replace: break
            case .fail: fail("herald: \(HeraldTemplateBundle.BundleError.nameExists(bundled).localizedDescription) for \(app); use --keep-both or --replace")
            }
        }
        var (template, report) = try HeraldTemplateBundle.installAssets(
            contents, into: HeraldTemplateBundle.assetsFolder(app: app, supportDirectory: supportDir))
        template.name = name
        template.app = app

        var put = CLIRequest(method: "PUT", path: "/v1/templates")
        guard let json = try? JSONSerialization.jsonObject(with: HeraldJSON.encoder().encode(template)) as? [String: Any] else {
            fail("herald: could not encode the template")
        }
        put.body = json
        let (status, data) = send(put, to: target)
        guard (200..<300).contains(status) else {
            fail("herald: Herald refused the template (HTTP \(status)): \(String(data: data, encoding: .utf8) ?? "")")
        }
        for m in report.missing { FileHandle.standardError.write(Data("herald: the animation \u{201C}\(m)\u{201D} is not in the bundle and not installed\n".utf8)) }
        let note = name == bundled ? "" : " (the name \u{201C}\(bundled)\u{201D} was taken)"
        print("Imported \u{201C}\(name)\u{201D} for \(app)\(note); \(report.installed.count) new animation file\(report.installed.count == 1 ? "" : "s"), \(report.reused.count) already there")
        exit(0)
    } catch {
        fail("herald: \(error.localizedDescription)")
    }
}
