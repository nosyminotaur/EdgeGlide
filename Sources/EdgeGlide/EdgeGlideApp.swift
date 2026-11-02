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
        let state = AppState()
        self.state = state
        // Debug only: `--render-screenshots <dir>` writes the README
        // screenshots and quits. See "Update the screenshots" in README.md.
        if let dir = ScreenshotRenderer.requestedDirectory() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                ScreenshotRenderer.run(state: state, into: dir)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("EdgeGlide", systemImage: AppSymbol.menuBar) {
            PanelView(state: state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state)
        }
    }
}

/// SF Symbols the app uses in more than one place. Each one was checked to
/// exist on macOS 14 and later.
enum AppSymbol {
    static let menuBar = "rectangle.and.hand.point.up.left"

    static func icon(for zone: GestureZone) -> String {
        switch zone {
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .mute: "speaker.slash.fill"
        case .tracks: "forward.end.fill"
        }
    }
}
