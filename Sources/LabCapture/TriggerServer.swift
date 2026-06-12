import Foundation
import Network

/// 로컬 HTTP 제어 서버 (127.0.0.1:48620 — 루프백 전용, 외부 노출 없음).
/// 사람(git hook의 curl)과 LLM/봇 에이전트가 같은 API로 앱을 제어한다.
/// 라우팅은 AppModel이 핸들러로 주입한다. GET /capabilities 가 머신리더블 API 명세.
final class TriggerServer {
    static let port: UInt16 = 48620

    /// (method, path, respond(statusCode, jsonBody)) — respond는 아무 스레드에서나 호출 가능
    typealias Route = @Sendable (_ method: String, _ path: String,
                                 _ respond: @escaping @Sendable (Int, String) -> Void) -> Void

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "labcapture.trigger")

    func start(route: @escaping Route) {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: NWEndpoint.Port(rawValue: Self.port)!
            )
            let l = try NWListener(using: params)
            l.newConnectionHandler = { conn in
                conn.start(queue: self.queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    let req = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let firstLine = req.split(separator: "\r\n").first.map(String.init) ?? ""
                    let parts = firstLine.split(separator: " ")
                    let method = parts.count > 0 ? String(parts[0]) : "GET"
                    let rawPath = parts.count > 1 ? String(parts[1]) : "/"
                    let path = rawPath.split(separator: "?").first.map(String.init) ?? "/"

                    route(method, path) { code, body in
                        let statusText: String
                        switch code {
                        case 200: statusText = "200 OK"
                        case 202: statusText = "202 Accepted"
                        case 400: statusText = "400 Bad Request"
                        case 404: statusText = "404 Not Found"
                        case 409: statusText = "409 Conflict"
                        default: statusText = "\(code) Status"
                        }
                        let payload = body.hasSuffix("\n") ? body : body + "\n"
                        let resp = "HTTP/1.1 \(statusText)\r\n" +
                            "Content-Type: application/json; charset=utf-8\r\n" +
                            "Content-Length: \(payload.utf8.count)\r\n" +
                            "Connection: close\r\n\r\n" + payload
                        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in
                            conn.cancel()
                        })
                    }
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            NSLog("LabCapture: trigger server failed to start (port \(Self.port)): \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
