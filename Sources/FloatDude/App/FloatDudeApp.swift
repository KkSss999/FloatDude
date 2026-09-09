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
    @ObservedObject private var settingsStore: SettingsStore

    init(runtime: AppRuntime) {
        self.runtime = runtime
        self._settingsStore = ObservedObject(wrappedValue: runtime.settingsStore)
    }

    private var copy: ProductCopy {
        ProductCopy(language: settingsStore.current.settingsLanguage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FloatDude")
                .font(.headline)
            Text(copy.text(.menuReady))
                .foregroundStyle(.secondary)
            if let startupError = runtime.startupError {
                Label(startupError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Button(copy.text(.menuAsk)) {
                runtime.coordinator.beginInvocation()
            }
            Button(copy.text(.menuNewConversation)) {
                runtime.startNewConversation()
            }
            Button(copy.text(.menuExports)) {
                runtime.openExportsFolder()
            }
            Button(copy.text(.menuSettings)) {
                runtime.openSettings()
            }
            Button(copy.text(.menuQuit)) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 220)
    }
}
