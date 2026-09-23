import Foundation
import CryptoKit

// MARK: - voicequick_clipboard.py / ClipboardSyncService.swift と同じフィールド名で往復できる形

struct ClipboardItem: Codable, Equatable {
    var revision: Int?
    let id: String
    let originDevice: String
    let text: String
    let contentHash: String
    let createdAt: String
    let targets: [String]
}

struct ClipboardItemInput: Decodable {
    let id: String?
    let originDevice: String?
    let text: String
    let contentHash: String?
    let createdAt: String?
    let targets: [String]?
}

enum ClipboardHash {
    static func of(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum ClipboardTime {
    // Pythonのnow_iso()(秒精度+Z終端)、iOS側のJSONDecoder.dateDecodingStrategy = .iso8601 と同じ形式。
    static func nowISO8601() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}
