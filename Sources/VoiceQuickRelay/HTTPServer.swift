import Foundation
import Network

// MARK: - voicequick_clipboard.pyのRelayServer/RelayHandler相当。Network.frameworkだけで実装(外部依存なし)。
final class HTTPServer {
    private var listener: NWListener?
    private let store: ClipboardStore
    private var token: String
    private let port: NWEndpoint.Port

    init?(port: UInt16, token: String, store: ClipboardStore) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return nil }
        self.port = endpointPort
        self.token = token
        self.store = store
    }

    func updateToken(_ newToken: String) {
        token = newToken
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                FileHandle.standardError.write(Data("[relay] listener failed (port in use?): \(error)\n".utf8))
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data, !data.isEmpty {
                buffer.append(data)
            }
            if let request = HTTPRequestParser.parse(buffer) {
                let response = self.route(request)
                connection.send(content: response.serialize(), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: buffer)
        }
    }

    private func route(_ request: HTTPRequest) -> HTTPResponse {
        guard isAuthorized(request) else {
            return .json(status: 401, ErrorPayload(error: "unauthorized"))
        }
        switch (request.method, request.path) {
        case ("GET", "/v1/clipboard/health"):
            return .json(status: 200, HealthPayload(status: "ok", service: "voicequick-clipboard"))

        case ("GET", "/v1/clipboard/latest"):
            let device = request.queryItems["device_id"] ?? request.headers["x-voicequick-device"] ?? "unknown"
            let platform = request.queryItems["platform"] ?? "all"
            let after = Int(request.queryItems["after_revision"] ?? "0") ?? 0
            if let item = store.latest(excludingDevice: device, platform: platform, afterRevision: after) {
                return .json(status: 200, item)
            }
            return .empty(status: 204)

        case ("POST", "/v1/clipboard"):
            guard let body = request.body,
                  let incoming = try? JSONDecoder().decode(ClipboardItemInput.self, from: body),
                  !incoming.text.isEmpty
            else {
                return .json(status: 400, ErrorPayload(error: "invalid_text"))
            }
            let item = ClipboardItem(
                revision: nil,
                id: incoming.id ?? UUID().uuidString,
                originDevice: incoming.originDevice ?? request.headers["x-voicequick-device"] ?? "unknown",
                text: incoming.text,
                contentHash: incoming.contentHash ?? ClipboardHash.of(incoming.text),
                createdAt: incoming.createdAt ?? ClipboardTime.nowISO8601(),
                targets: incoming.targets ?? ["all"]
            )
            let saved = store.put(item)
            return .json(status: 200, saved)

        default:
            return .json(status: 404, ErrorPayload(error: "not_found"))
        }
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        guard !token.isEmpty else { return true }
        return request.headers["authorization"] == "Bearer \(token)"
    }
}
