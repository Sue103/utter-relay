import Foundation

// MARK: - 最小限の自前HTTP/1.1パーサー(voicequick_clipboard.pyのhttp.serverと同等の役割)

struct HTTPRequest {
    let method: String
    let path: String
    let queryItems: [String: String]
    let headers: [String: String] // キーは小文字化済み
    let body: Data?
}

enum HTTPRequestParser {
    /// バッファがまだ完全なリクエストになっていなければnilを返す(呼び出し側は受信を続ける)。
    static func parse(_ buffer: Data) -> HTTPRequest? {
        guard let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer[..<headerEndRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let fullPath = String(parts[1])
        let pathComponents = fullPath.split(separator: "?", maxSplits: 1)
        let path = String(pathComponents[0])

        var queryItems: [String: String] = [:]
        if pathComponents.count > 1 {
            for pair in pathComponents[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                guard kv.count == 2 else { continue }
                queryItems[String(kv[0]).removingPercentEncoding ?? String(kv[0])] =
                    String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let bodyStart = headerEndRange.upperBound
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let availableBody = buffer.count - bodyStart
        guard availableBody >= contentLength else { return nil }
        let body: Data? = contentLength > 0 ? Data(buffer[bodyStart..<bodyStart + contentLength]) : nil
        return HTTPRequest(method: method, path: path, queryItems: queryItems, headers: headers, body: body)
    }
}

struct HTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: Data

    static func json<T: Encodable>(status: Int, _ value: T) -> HTTPResponse {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: data)
    }

    static func empty(status: Int) -> HTTPResponse {
        HTTPResponse(status: status, headers: [:], body: Data())
    }

    func serialize() -> Data {
        var responseHeaders = headers
        responseHeaders["Content-Length"] = "\(body.count)"
        responseHeaders["Connection"] = "close"
        var head = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        for (key, value) in responseHeaders {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        default: return "Unknown"
        }
    }
}

struct ErrorPayload: Codable { let error: String }
struct HealthPayload: Codable { let status: String; let service: String }
