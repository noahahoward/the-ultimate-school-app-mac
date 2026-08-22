import Foundation
import Network

/// A single-use HTTP listener on 127.0.0.1 that catches the OAuth redirect.
///
/// It answers exactly one request, shows the student a "you can close this tab"
/// page, and hands the query parameters back to the caller.
final class LoopbackListener {

    struct Result {
        var code: String?
        var state: String?
        var error: String?
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.locker.oauth.loopback")
    private var continuation: CheckedContinuation<Result, Error>?
    private var hasFinished = false
    private var connections: [NWConnection] = []

    let port: UInt16

    init() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Binding to 0 lets the OS pick a free port, which is what Google's
        // installed-app flow expects.
        guard let listener = try? NWListener(using: parameters, on: .any) else {
            throw ImportError.network("Could not open a local port for sign-in.")
        }
        self.listener = listener

        let ready = DispatchSemaphore(value: 0)
        var boundPort: UInt16 = 0
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                boundPort = listener.port?.rawValue ?? 0
                ready.signal()
            }
            if case .failed = state { ready.signal() }
        }
        listener.start(queue: queue)

        guard ready.wait(timeout: .now() + 5) == .success, boundPort != 0 else {
            listener.cancel()
            throw ImportError.network("Could not open a local port for sign-in.")
        }
        self.port = boundPort
    }

    func waitForRedirect(timeout: TimeInterval) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else { return }
                self.continuation = continuation

                self.listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }

                self.queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finish(.failure(ImportError.cancelled))
                }
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
            let result = Self.parse(request: request)
            self.respond(on: connection, success: result.error == nil && result.code != nil)
            self.finish(.success(result))
        }
    }

    private func respond(on connection: NWConnection, success: Bool) {
        let title = success ? "You&rsquo;re connected" : "Sign-in didn&rsquo;t finish"
        let message = success
            ? "Locker is syncing your classes. You can close this tab."
            : "Nothing was changed. Head back to Locker and try again."

        let body = """
        <!doctype html><html><head><meta charset="utf-8"><title>Locker</title>
        <style>
          :root { color-scheme: light dark; }
          body { font-family: -apple-system, system-ui, sans-serif; display: grid;
                 place-items: center; height: 100vh; margin: 0; text-align: center; }
          .card { max-width: 26rem; padding: 2rem; }
          h1 { font-size: 1.4rem; margin: 0 0 .5rem; }
          p { opacity: .7; margin: 0; line-height: 1.5; }
        </style></head>
        <body><div class="card"><h1>\(title)</h1><p>\(message)</p></div></body></html>
        """

        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ outcome: Swift.Result<Result, Error>) {
        guard !hasFinished else { return }
        hasFinished = true
        let continuation = self.continuation
        self.continuation = nil
        switch outcome {
        case .success(let value): continuation?.resume(returning: value)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            self.connections.forEach { $0.cancel() }
            self.connections.removeAll()
            self.listener.cancel()
        }
    }

    /// Pulls the query parameters out of the request line of a raw HTTP request.
    static func parse(request: String) -> Result {
        guard let line = request.split(separator: "\r\n").first ?? request.split(separator: "\n").first else {
            return Result()
        }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return Result() }
        let path = String(parts[1])

        guard let components = URLComponents(string: "http://127.0.0.1\(path)") else { return Result() }
        let items = components.queryItems ?? []
        return Result(
            code: items.first { $0.name == "code" }?.value,
            state: items.first { $0.name == "state" }?.value,
            error: items.first { $0.name == "error" }?.value
        )
    }
}
