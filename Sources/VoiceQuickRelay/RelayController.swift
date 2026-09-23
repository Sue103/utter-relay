import Foundation
import Combine

@MainActor
final class RelayController: ObservableObject {
    @Published var isRunning = false
    @Published var statusMessage = "停止中"
    @Published var lastEvent = ""

    @Published var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: Keys.port) }
    }
    @Published var token: String {
        didSet {
            UserDefaults.standard.set(token, forKey: Keys.token)
            server?.updateToken(token)
            agent?.token = token
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { LaunchAtLogin.setEnabled(launchAtLogin) }
    }

    private var server: HTTPServer?
    private var agent: LocalClipboardAgent?
    private let store: ClipboardStore
    private let deviceID: String

    private enum Keys {
        static let port = "relayPort"
        static let token = "relayToken"
        static let launchAtLogin = "launchAtLogin"
        static let deviceID = "relayDeviceID"
        static let autoStart = "relayAutoStart"
    }

    init() {
        let defaults = UserDefaults.standard
        port = defaults.object(forKey: Keys.port) as? Int ?? 7210
        token = defaults.string(forKey: Keys.token) ?? ""
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

        if let savedID = defaults.string(forKey: Keys.deviceID) {
            deviceID = savedID
        } else {
            let newID = "mac-\(UUID().uuidString.prefix(8).lowercased())"
            deviceID = newID
            defaults.set(newID, forKey: Keys.deviceID)
        }

        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceQuickRelay", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        store = ClipboardStore(fileURL: supportDir.appendingPathComponent("clipboard.json"))

        if defaults.object(forKey: Keys.autoStart) as? Bool ?? true {
            start()
        }
    }

    func start() {
        guard !isRunning else { return }
        guard let server = HTTPServer(port: UInt16(port), token: token, store: store) else {
            statusMessage = "ポート番号が不正です"
            return
        }
        do {
            try server.start()
        } catch {
            statusMessage = "起動失敗: \(error.localizedDescription)"
            return
        }
        self.server = server

        let relayURL = URL(string: "http://127.0.0.1:\(port)")!
        let agent = LocalClipboardAgent(deviceID: deviceID, relayURL: relayURL, token: token)
        agent.onEvent = { [weak self] message in
            Task { @MainActor in self?.lastEvent = message }
        }
        agent.start()
        self.agent = agent

        isRunning = true
        statusMessage = "実行中(ポート \(port))"
        UserDefaults.standard.set(true, forKey: Keys.autoStart)
    }

    func stop() {
        server?.stop()
        agent?.stop()
        server = nil
        agent = nil
        isRunning = false
        statusMessage = "停止中"
        UserDefaults.standard.set(false, forKey: Keys.autoStart)
    }

    func restart() {
        stop()
        start()
    }

    var localIPAddress: String {
        NetworkAddress.currentLANAddress() ?? "取得できません"
    }

    var deviceIdentifier: String { deviceID }
}
