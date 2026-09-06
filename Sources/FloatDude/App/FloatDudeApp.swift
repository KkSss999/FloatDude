import AppKit
import SwiftUI

@main
struct FloatDudeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("FloatDude", systemImage: "sparkles") {
            MenuBarPlaceholderView()
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FloatDude")
                .font(.headline)
            Text("0.1.0 project scaffold")
                .foregroundStyle(.secondary)
            Divider()
            Button("Quit FloatDude") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 220)
    }
}
