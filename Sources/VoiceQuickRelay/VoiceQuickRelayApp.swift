import SwiftUI

@main
struct VoiceQuickRelayApp: App {
    @StateObject private var controller = RelayController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(controller: controller)
        } label: {
            Image(systemName: controller.isRunning ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
