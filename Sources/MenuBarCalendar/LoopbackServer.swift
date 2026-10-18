import Foundation
import Network

/// Catches Google's OAuth redirect on http://127.0.0.1:<port>/ — this is
/// Google's "loopback IP" flow for installed apps: the system browser opens
/// for consent, then Google redirects back to this local server with the
/// authorization code in the query string. No custom URL scheme needed.
final class LoopbackServer {
    enum ServerError: Error { case missingCode, listenerFailed }

    let port: UInt16 = 8991
    private var listener: NWListener?

    var redirectURI: String { "http://127.0.0.1:\(port)/" }

    func waitForCode(completion: @escaping (Result<String, Error>) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(.failure(ServerError.listenerFailed))
            return
        }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: nwPort)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                print("[LoopbackServer] incoming connection")
                self?.handle(connection, completion: completion)
            }
            listener.stateUpdateHandler = { state in
                print("[LoopbackServer] listener state: \(state)")
            }
            listener.start(queue: .main)
        } catch {
            print("[LoopbackServer] failed to start: \(error)")
            completion(.failure(error))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection, completion: @escaping (Result<String, Error>) -> Void) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                print("[LoopbackServer] receive error: \(error)")
                connection.cancel()
                self.stop()
                completion(.failure(error))
                return
            }

            guard
                let data,
                let requestLine = String(data: data, encoding: .utf8)?
                    .components(separatedBy: "\r\n").first,
                let path = requestLine.components(separatedBy: " ").dropFirst().first,
                let components = URLComponents(string: "http://localhost\(path)")
            else {
                print("[LoopbackServer] could not parse request")
                connection.cancel()
                self.stop()
                completion(.failure(ServerError.missingCode))
                return
            }

            print("[LoopbackServer] request path: \(path)")

            guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                let errorParam = components.queryItems?.first(where: { $0.name == "error" })?.value
                print("[LoopbackServer] no code in redirect, error param: \(errorParam ?? "none")")
                connection.cancel()
                self.stop()
                completion(.failure(ServerError.missingCode))
                return
            }

            let body = """
            <html><body style="font-family: -apple-system; padding: 40px;">
            <h2>Connected. You can close this tab.</h2>
            </body></html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            // Only cancel/stop once the response has actually been flushed —
            // doing it in a `defer` on the outer closure fired before this
            // async send completed, resetting the connection before Safari
            // got the response.
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { sendError in
                if let sendError {
                    print("[LoopbackServer] send error: \(sendError)")
                }
                connection.cancel()
                self.stop()
                completion(.success(code))
            })
        }
    }
}
