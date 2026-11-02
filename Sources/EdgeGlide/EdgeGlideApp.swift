import AppKit
import EdgeGlideCore
import SwiftUI

@main
struct EdgeGlideApp: App {
    // `@State` is a macro in this SDK, and the Command Line Tools ship no
    // SwiftUIMacros plugin. SwiftUI creates the App value once, so a plain
    // stored reference holds the single AppState for the process lifetime.
    private let state: AppState

    init() {
        state = AppState()
    }

    var body: some Scene {
        MenuBarExtra("EdgeGlide", systemImage: "hand.draw") {
            MenuView(state: state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(state: state)
        }
    }
}

struct MenuView: View {
    @Bindable var state: AppState

    var body: some View {
        Toggle("Gestures enabled", isOn: $state.enabled)
        Divider()
        Text(state.trackpadStatus)
        Text(state.volumeStatus)
        Text(state.brightnessStatus)
        Text(state.mediaStatus)
        Text(state.hapticsStatus)
        Text(state.loginStatus)
        if let action = state.lastAction { Text("Last: \(action)") }
        if let error = state.lastError { Text("Error: \(error)") }
        Divider()
        Button("Refresh status") { state.refreshStatus() }
        Button("Rescan trackpads") { state.startMonitor(); state.refreshStatus() }
        if state.mediaStatus.contains("need Accessibility") {
            Button("Allow media keys…") { state.requestMediaKeyAccess() }
        }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit EdgeGlide") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section("Gestures") {
                Toggle("Right edge: volume", isOn: $state.volumeEnabled)
                Toggle("Left edge: brightness", isOn: $state.brightnessEnabled)
                Toggle("Top-right double-tap: mute", isOn: $state.muteEnabled)
                Toggle("Bottom swipe: next and previous track", isOn: $state.mediaEnabled)
            }
            Section("Feel") {
                LabeledContent("Edge width") {
                    Slider(value: $state.edgeWidth, in: 0.05...0.25)
                    Text("\(Int((state.edgeWidth * 100).rounded()))%").monospacedDigit().frame(width: 44)
                }
                LabeledContent("Sensitivity") {
                    Slider(value: $state.sensitivity, in: 0.5...3.0)
                    Text(String(format: "%.1f×", state.sensitivity)).monospacedDigit().frame(width: 44)
                }
                Picker("Haptic strength", selection: $state.hapticStrength) {
                    ForEach(HapticStrength.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("System") {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }))
                Text(state.loginStatus).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(.vertical, 8)
        .onAppear { NSApp.activate() }
    }
}
