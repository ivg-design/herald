import Foundation

/// How a `callback` button's POST is delivered: a hard 5 s budget per attempt and one retry.
public struct CallbackPolicy: Equatable, Sendable {
    /// Seconds one attempt may take in total (connect + request + response).
    public var timeout: TimeInterval
    /// Extra attempts after the first one.
    public var retries: Int
    /// Pause before a retry. Long enough for a client that was just restarting, short enough that the
    /// banner does not look dead.
    public var retryDelay: TimeInterval

    public init(timeout: TimeInterval = 5, retries: Int = 1, retryDelay: TimeInterval = 0.75) {
        self.timeout = timeout; self.retries = retries; self.retryDelay = retryDelay
    }

    public static let standard = CallbackPolicy()
}

public enum CallbackOutcome: Equatable, Sendable {
    case delivered(attempts: Int)
    /// `reason` is short and fit for a log line and for the banner ("HTTP 500", "timed out after 5 s").
    case failed(attempts: Int, reason: String)

    public var isDelivered: Bool { if case .delivered = self { return true } else { return false } }
    public var failureReason: String? { if case .failed(_, let r) = self { return r } else { return nil } }
}

/// POSTs a `HeraldCallbackEvent` to a client's callback URL.
///
/// The event carries the payload the sender attached to the button, so where it goes matters: a loopback
/// address is always fine (that is what every local app registers), any other host only when the caller says
/// the user approved it (`approvedHosts`), and a redirect is never followed, so an approved host cannot pass
/// the body on to a host nobody approved.
///
/// Success is any 2xx. A transport error (refused, reset, timed out) and the statuses that mean "try again
/// later" (408, 429, 5xx) are retried once; every other 4xx is a deterministic rejection, so retrying would
/// only repeat it. The event carries `notificationId` and `action`, which is what a receiver needs to
/// de-duplicate the rare case where the first attempt did reach it but its answer was lost.
public final class CallbackDelivery: @unchecked Sendable {
    private let policy: CallbackPolicy
    private let session: URLSession
    private let log: @Sendable (String) -> Void

    public init(policy: CallbackPolicy = .standard,
                log: @escaping @Sendable (String) -> Void = { NSLog("Herald: %@", $0) }) {
        self.policy = policy
        self.log = log
        let c = URLSessionConfiguration.ephemeral
        // Request timeout alone is an *idle* timeout (a server dribbling bytes could hold it open for ever);
        // the resource timeout is the real wall-clock cap for one attempt.
        c.timeoutIntervalForRequest = policy.timeout
        c.timeoutIntervalForResource = policy.timeout
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: c, delegate: NoRedirects(), delegateQueue: nil)
    }

    /// Answers every redirect with "do not follow", so the 3xx itself comes back as the response.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    /// Lower-cased host of `url` without brackets or port, nil when it has none.
    public static func normalizedHost(of url: URL) -> String? {
        guard let h = url.host?.lowercased(), !h.isEmpty else { return nil }
        return h
    }

    /// `127.0.0.1`, `::1` and `localhost`.
    public static func isLoopback(host: String) -> Bool {
        ["127.0.0.1", "::1", "localhost"].contains(host.lowercased())
    }

    /// True when a callback to `url` needs the user's approval (it does not go to a loopback address).
    public static func needsApproval(_ url: URL) -> Bool {
        guard let host = normalizedHost(of: url) else { return true }
        return !isLoopback(host: host)
    }

    /// `approvedHosts` are lower-case hosts the user agreed callbacks may go to.
    public func deliver(_ event: HeraldCallbackEvent, to url: URL, approvedHosts: Set<String> = []) async -> CallbackOutcome {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            let reason = "unsupported callback URL scheme"
            log("callback \(event.action) for \(event.app)/\(event.notificationId): \(reason): \(url.absoluteString)")
            return .failed(attempts: 0, reason: reason)
        }
        if Self.needsApproval(url), !(Self.normalizedHost(of: url).map(approvedHosts.contains) ?? false) {
            let reason = "callback host not approved"
            log("callback \(event.action) for \(event.app)/\(event.notificationId): \(reason): \(url.host ?? url.absoluteString)")
            return .failed(attempts: 0, reason: reason)
        }
        guard let body = try? HeraldJSON.encoder().encode(event) else {
            return .failed(attempts: 0, reason: "could not encode the callback event")
        }

        let total = 1 + max(0, policy.retries)
        var reason = "unknown error"
        for attempt in 1...total {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = body
            req.timeoutInterval = policy.timeout
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(String(attempt), forHTTPHeaderField: "X-Herald-Attempt")
            let result: (reason: String, retryable: Bool)
            do {
                let (_, response) = try await session.data(for: req)
                if let http = response as? HTTPURLResponse {
                    if (200..<300).contains(http.statusCode) { return .delivered(attempts: attempt) }
                    result = ("HTTP \(http.statusCode)", Self.isRetryable(status: http.statusCode))
                } else {
                    result = ("no HTTP response", true)
                }
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    return .failed(attempts: attempt, reason: "cancelled")
                }
                result = (describe(error), Self.isRetryable(error: error))
            }
            reason = result.reason
            log("callback \(event.action) for \(event.app)/\(event.notificationId) to \(url.absoluteString) failed: \(reason) (attempt \(attempt)/\(total))")
            guard result.retryable else { return .failed(attempts: attempt, reason: reason) }
            if attempt < total { await pause() }
        }
        return .failed(attempts: total, reason: reason)
    }

    private func pause() async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, policy.retryDelay) * 1_000_000_000))
    }

    public static func isRetryable(status: Int) -> Bool {
        status == 408 || status == 429 || (500..<600).contains(status)
    }

    public static func isRetryable(error: Error) -> Bool {
        guard let e = error as? URLError else { return true }
        switch e.code {
        case .cancelled, .badURL, .unsupportedURL: return false
        default: return true
        }
    }

    private func describe(_ error: Error) -> String {
        guard let e = error as? URLError else { return error.localizedDescription }
        switch e.code {
        case .timedOut: return "timed out after \(String(format: "%g", policy.timeout)) s"
        case .cannotConnectToHost: return "connection refused"
        case .networkConnectionLost: return "connection lost"
        case .cannotFindHost, .dnsLookupFailed: return "host not found"
        default: return e.localizedDescription
        }
    }
}
