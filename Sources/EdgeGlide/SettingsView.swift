import AppKit
import EdgeGlideCore
import SwiftUI

/// The Settings window: Gestures, Feel, and About tabs.
struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        TabView(selection: $state.settingsTab) {
            GesturesTab(state: state)
                .tabItem { Label("Gestures", systemImage: "hand.draw") }
                .tag(SettingsTab.gestures)
            FeelTab(state: state)
                .tabItem { Label("Feel", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.feel)
            AboutTab(state: state)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 460)
        .onAppear { NSApp.activate() }
    }
}

// MARK: - Gestures

struct GesturesTab: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section {
                GestureToggle(isOn: $state.volumeEnabled, zone: .volume, title: "Volume",
                              caption: "Slide one finger up or down along the right edge.")
                GestureToggle(isOn: $state.brightnessEnabled, zone: .brightness, title: "Brightness",
                              caption: "Slide one finger up or down along the left edge.")
                GestureToggle(isOn: $state.muteEnabled, zone: .mute, title: "Mute",
                              caption: "Double-tap the top-right corner.")
                GestureToggle(isOn: $state.mediaEnabled, zone: .tracks, title: "Next and previous track",
                              caption: "Swipe left or right along the bottom edge.")
            } footer: {
                Text("A gesture starts only when your finger lands inside its zone. Two or more fingers never trigger one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct GestureToggle: View {
    @Binding var isOn: Bool
    let zone: GestureZone
    let title: String
    let caption: String

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Image(systemName: AppSymbol.icon(for: zone))
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
    }
}

// MARK: - Feel

struct FeelTab: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section("Zones") {
                LabeledContent("Edge width") {
                    Slider(value: $state.edgeWidth, in: 0.05...0.25)
                    Text("\(Int((state.edgeWidth * 100).rounded()))%").monospacedDigit().frame(width: 44)
                }
                LabeledContent("Sensitivity") {
                    Slider(value: $state.sensitivity, in: 0.5...3.0)
                    Text(String(format: "%.1f×", state.sensitivity)).monospacedDigit().frame(width: 44)
                }
            }
            Section("Haptics") {
                LabeledContent("Strength") {
                    Picker("Strength", selection: $state.hapticStrength) {
                        ForEach(HapticStrength.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Test") { state.testHaptic() }
                        .disabled(state.hapticStrength == .off)
                }
            }
            Section("System") {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                Text(state.loginStatus).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutTab: View {
    @Bindable var state: AppState

    static var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "dev" }
        if let build = info?["CFBundleVersion"] as? String, build != short { return "\(short) (\(build))" }
        return short
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: AppSymbol.menuBar)
                        .font(.system(size: 34))
                        .foregroundStyle(.tint)
                        .frame(width: 52, height: 52)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("EdgeGlide").font(.title2.weight(.semibold))
                        Text("Version \(Self.version)").foregroundStyle(.secondary)
                        Text("Free and open source. MIT License.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                LabeledContent("Source code") {
                    Link("github.com/nosyminotaur/edgeglide",
                         destination: URL(string: "https://github.com/nosyminotaur/edgeglide")!)
                }
            }
            Section("Diagnostics") {
                ForEach(diagnostics, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Refresh status") { state.refreshStatus() }
                    Button("Rescan trackpads") { state.startMonitor(); state.refreshStatus() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var diagnostics: [String] {
        var lines = [state.trackpadStatus, state.volumeStatus, state.brightnessStatus,
                     state.mediaStatus, state.hapticsStatus, state.loginStatus]
        if let action = state.lastAction { lines.append("Last action: \(action)") }
        if let error = state.lastError { lines.append("Last error: \(error)") }
        return lines
    }
}
