import AppKit
import Foundation

// MARK: - voicequick_clipboard.pyのDesktopAgent相当。このMac自身のクリップボードを
// ローカルのリレー(127.0.0.1)へ同期する。ローカル変更直後はリモート上書きを見送る
// LOCAL_CHANGE_GRACE_SECONDSのロジック(v1.2.1で修正済みのもの)も忠実に移植する。
final class LocalClipboardAgent {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var lastLocalHash = ""
    private var lastAppliedHash = ""
    private var lastRevision = 0
    private var lastLocalChangeAt: TimeInterval = 0
    private let graceSeconds: TimeInterval = 3.0
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "voicequickrelay.agent")

    let deviceID: String
    let platformName = "mac"
    var relayURL: URL
    var token: String
    var interval: TimeInterval = 0.6
    var onEvent: ((String) -> Void)?

    init(deviceID: String, relayURL: URL, token: String) {
        self.deviceID = deviceID
        self.relayURL = relayURL
        self.token = token
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let currentChangeCount = pasteboard.changeCount
        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            if let text = pasteboard.string(forType: .string), !text.isEmpty {
                let hash = ClipboardHash.of(text)
                if hash != lastLocalHash {
                    lastLocalHash = hash
                    lastLocalChangeAt = ProcessInfo.processInfo.systemUptime
                    if hash != lastAppliedHash {
                        send(text: text, hash: hash)
                    }
                }
            }
        }

        fetchLatest { [weak self] remote in
            guard let self, let remote else { return }
            let justChangedLocally = (ProcessInfo.processInfo.systemUptime - self.lastLocalChangeAt) < self.graceSeconds
            guard remote.contentHash != self.lastLocalHash, !justChangedLocally else {
                if justChangedLocally {
                    self.onEvent?("見送り r\(remote.revision ?? 0)(直前にローカルで変更)")
                }
                return
            }
            DispatchQueue.main.async {
                self.pasteboard.clearContents()
                self.pasteboard.setString(remote.text, forType: .string)
                self.lastChangeCount = self.pasteboard.changeCount
            }
            self.lastRevision = remote.revision ?? self.lastRevision
            self.lastAppliedHash = remote.contentHash
            self.lastLocalHash = remote.contentHash
            self.onEvent?("受信 r\(remote.revision ?? 0) ← \(remote.originDevice)")
        }
    }

    private func send(text: String, hash: String) {
        guard !text.contains("\u{FFFD}") else { return }
        var request = URLRequest(url: relayURL.appendingPathComponent("v1/clipboard"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(&request)
        // デスクトップ→デスクトップ直接同期は元々想定しておらず、送信先は常にiPhoneのみ。
        let item = ClipboardItem(
            revision: nil,
            id: UUID().uuidString,
            originDevice: deviceID,
            text: text,
            contentHash: hash,
            createdAt: ClipboardTime.nowISO8601(),
            targets: ["iphone"]
        )
        request.httpBody = try? JSONEncoder().encode(item)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data, let saved = try? JSONDecoder().decode(ClipboardItem.self, from: data)
            else { return }
            self.lastRevision = max(self.lastRevision, saved.revision ?? 0)
            self.onEvent?("送信 r\(saved.revision ?? 0)")
        }.resume()
    }

    private func fetchLatest(completion: @escaping (ClipboardItem?) -> Void) {
        var components = URLComponents(url: relayURL.appendingPathComponent("v1/clipboard/latest"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "device_id", value: deviceID),
            URLQueryItem(name: "platform", value: platformName),
            URLQueryItem(name: "after_revision", value: String(lastRevision))
        ]
        guard let url = components?.url else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        applyHeaders(&request)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
                  let item = try? JSONDecoder().decode(ClipboardItem.self, from: data)
            else {
                completion(nil)
                return
            }
            completion(item)
        }.resume()
    }

    private func applyHeaders(_ request: inout URLRequest) {
        request.setValue(deviceID, forHTTPHeaderField: "X-VoiceQuick-Device")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}
