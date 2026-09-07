import AppKit
import SwiftUI

@main
struct FloatDudeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime = AppRuntime.shared

    var body: some Scene {
        MenuBarExtra("FloatDude", systemImage: "sparkles") {
            MenuBarView(runtime: runtime)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FloatDude")
                .font(.headline)
            Text("Ready in the menu bar")
                .foregroundStyle(.secondary)
            if let startupError = runtime.startupError {
                Label(startupError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Button("Ask FloatDude…") {
                runtime.coordinator.beginInvocation()
            }
            Button("Settings…") {
                runtime.openSettings()
            }
            Button("Quit FloatDude") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 220)
    }
}
