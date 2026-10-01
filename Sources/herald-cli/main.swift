import Foundation
import HeraldClient

// Thin driver: all parsing lives in HeraldClient/CLIArguments.swift.

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let supportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Herald")

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
    let port = invocation.port ?? readTrimmed("port").flatMap(Int.init) ?? CLIArguments.defaultPort
    let token = invocation.token ?? readTrimmed("token")

    var comps = URLComponents()
    comps.scheme = "http"; comps.host = "127.0.0.1"; comps.port = port; comps.path = req.path
    if !req.query.isEmpty { comps.queryItems = req.query.map { URLQueryItem(name: $0.name, value: $0.value) } }
    guard let url = comps.url else { fail("herald: could not build request URL") }

    var request = URLRequest(url: url, timeoutInterval: 15)
    request.httpMethod = req.method
    if req.needsAuth, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body = req.body {
        do { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        catch { fail("herald: payload is not valid JSON: \(error.localizedDescription)") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

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
    let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
    let data = result.0 ?? Data()
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
}
