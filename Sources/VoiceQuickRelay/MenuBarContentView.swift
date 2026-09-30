import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @ObservedObject var controller: RelayController
    @State private var portText: String = ""
    @State private var tokenText: String = ""
    @State private var copiedFeedback = false
    @State private var showQRCode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(controller.isRunning ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(controller.statusMessage)
                    .font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { controller.isRunning },
                    set: { newValue in newValue ? controller.start() : controller.stop() }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("このMacのアドレス(iPhone/Windowsに設定)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("http://\(controller.localIPAddress):\(String(controller.port))")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        copyAddress()
                    } label: {
                        Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    showQRCode.toggle()
                } label: {
                    Label(showQRCode ? "QRコードを隠す" : "QRコードで接続", systemImage: "qrcode")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)

                if showQRCode, let qrImage = QRCodeGenerator.generate(from: pairingPayload) {
                    HStack {
                        Spacer()
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 160, height: 160)
                            .padding(8)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                    Text("Utterの設定 → 「QRコードで読み取る」でスキャンしてください")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("ポート")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("7210", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyPort)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("ペアリングトークン(任意・両端末で一致させる)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("未設定", text: $tokenText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { controller.token = tokenText }
            }

            Toggle("ログイン時に自動起動", isOn: $controller.launchAtLogin)
                .toggleStyle(.checkbox)

            if !controller.lastEvent.isEmpty {
                Divider()
                Text(controller.lastEvent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            Button("終了") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            portText = String(controller.port)
            tokenText = controller.token
        }
    }

    private struct PairingPayload: Encodable {
        let relayURL: String
        let token: String
    }

    private var pairingPayload: String {
        let payload = PairingPayload(
            relayURL: "http://\(controller.localIPAddress):\(controller.port)",
            token: controller.token
        )
        guard let data = try? JSONEncoder().encode(payload) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func applyPort() {
        guard let value = Int(portText), (1024...65535).contains(value) else {
            portText = String(controller.port)
            return
        }
        controller.port = value
        if controller.isRunning { controller.restart() }
    }

    private func copyAddress() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("http://\(controller.localIPAddress):\(controller.port)", forType: .string)
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedFeedback = false }
    }
}
