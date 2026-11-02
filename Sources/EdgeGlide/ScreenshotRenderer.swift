import AppKit
import SwiftUI

/// Debug-only helper that writes the Settings screenshots for the README.
///
/// It runs only when the app starts with `--render-screenshots <dir>`. It
/// opens the real Settings window, shows each tab, and draws the window with
/// `cacheDisplay`, so it needs no Screen Recording permission. Nothing here
/// runs in normal use. The menu bar panel can't be opened from inside the
/// app, so it is drawn in an offscreen window instead.
@MainActor
enum ScreenshotRenderer {
    static func requestedDirectory() -> URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-screenshots"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func run(state: AppState, into dir: URL) {
        // Never hang: give up after 30 seconds.
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            FileHandle.standardError.write(Data("Screenshot render timed out\n".utf8))
            exit(2)
        }
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try await renderPanel(state: state, into: dir)
                try await captureSettings(state: state, into: dir)
                print("Wrote screenshots to \(dir.path)")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Screenshot render failed: \(error)\n".utf8))
                exit(1)
            }
        }
    }

    struct RenderError: Error, CustomStringConvertible {
        let description: String
    }

    /// Draws the panel offscreen with one zone lit. `ImageRenderer` can't
    /// draw AppKit-backed controls such as the switch and buttons, so the
    /// panel goes into an offscreen window and is drawn with `cacheDisplay`.
    private static func renderPanel(state: AppState, into dir: URL) async throws {
        state.activeZone = .volume
        defer { state.activeZone = nil }
        let host = NSHostingView(rootView: PanelView(state: state).background(.regularMaterial))
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: host.fittingSize),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(500))
        try write(window, name: "screenshot-panel", in: dir)
        window.orderOut(nil)
    }

    /// Opens the real Settings window through the app menu's Settings item,
    /// then draws each tab.
    private static func captureSettings(state: AppState, into dir: URL) async throws {
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        guard let item = findSettingsItem(in: NSApp.mainMenu), let menu = item.menu else {
            throw RenderError(description: "Settings menu item not found")
        }
        menu.performActionForItem(at: menu.index(of: item))
        try await Task.sleep(for: .milliseconds(800))
        guard let window = NSApp.windows.first(where: { !before.contains(ObjectIdentifier($0)) && $0.isVisible }) else {
            throw RenderError(description: "Settings window did not open")
        }
        for tab in SettingsTab.allCases {
            state.settingsTab = tab
            try await Task.sleep(for: .milliseconds(700))
            try write(window, name: "screenshot-settings-\(tab.rawValue)", in: dir)
        }
        state.settingsTab = .gestures
        try await Task.sleep(for: .milliseconds(700))
        try write(window, name: "screenshot-settings", in: dir)
        window.close()
    }

    private static func findSettingsItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }
        for item in menu.items {
            if item.title.hasPrefix("Settings") { return item }
            if let found = findSettingsItem(in: item.submenu) { return found }
        }
        return nil
    }

    /// Draws a window, title bar included, into a PNG.
    private static func write(_ window: NSWindow, name: String, in dir: URL) throws {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw RenderError(description: "no view to draw for \(name)")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw RenderError(description: "PNG encoding failed for \(name)")
        }
        try png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
