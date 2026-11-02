import AppKit
import SwiftUI

/// The popover that opens from the menu bar icon.
struct PanelView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            TrackpadDiagram(state: state)
                .opacity(state.enabled ? 1 : 0.45)
            StatusLine(state: state)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: AppSymbol.menuBar)
                .font(.title3)
                .foregroundStyle(.tint)
            Text("EdgeGlide").font(.headline)
            Spacer()
            Toggle("Gestures enabled", isOn: $state.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private var footer: some View {
        HStack {
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
    }
}

// MARK: - Trackpad diagram

/// A drawing of the trackpad with its four gesture zones.
///
/// Zone sizes follow the recognizer: the left and right edges are
/// `edgeWidth` wide, and the corner and bottom zones use the recognizer's
/// default 15%.
struct TrackpadDiagram: View {
    @Bindable var state: AppState

    private let cornerSize = 0.15
    private let bottomHeight = 0.15

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let edge = state.edgeWidth * w
            let corner = cornerSize * w
            let cornerH = cornerSize * h
            let bottom = bottomHeight * h

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quinary)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)

                zone(.brightness, size: CGSize(width: edge, height: h), at: .zero,
                     corners: .init(topLeading: 12, bottomLeading: 12))
                zone(.volume, size: CGSize(width: edge, height: h), at: CGPoint(x: w - edge, y: 0),
                     corners: .init(bottomTrailing: 12, topTrailing: 12))
                zone(.tracks, size: CGSize(width: w - 2 * edge, height: bottom),
                     at: CGPoint(x: edge, y: h - bottom), corners: .init())
                zone(.mute, size: CGSize(width: corner, height: cornerH),
                     at: CGPoint(x: w - corner, y: 0), corners: .init(topTrailing: 12))

                Text("Pointer area")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: w, height: h)
            }
        }
        .aspectRatio(1.6, contentMode: .fit)
        .animation(.easeOut(duration: 0.25), value: state.activeZone)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trackpad zones: right edge volume, left edge brightness, top-right corner mute, bottom edge tracks")
    }

    private func isOn(_ zone: GestureZone) -> Bool {
        switch zone {
        case .volume: state.volumeEnabled
        case .brightness: state.brightnessEnabled
        case .mute: state.muteEnabled
        case .tracks: state.mediaEnabled
        }
    }

    @ViewBuilder
    private func zone(_ zone: GestureZone, size: CGSize, at origin: CGPoint, corners: RectangleCornerRadii) -> some View {
        let on = isOn(zone)
        let lit = on && state.enabled && state.activeZone == zone
        let shape = UnevenRoundedRectangle(cornerRadii: corners, style: .continuous)
        ZStack {
            shape.fill(on ? AnyShapeStyle(Color.accentColor.opacity(lit ? 0.6 : 0.18)) : AnyShapeStyle(.quaternary))
            shape.strokeBorder(on ? AnyShapeStyle(Color.accentColor.opacity(0.45)) : AnyShapeStyle(.separator), lineWidth: 0.5)
            label(zone)
                .foregroundStyle(on ? AnyShapeStyle(lit ? .primary : .secondary) : AnyShapeStyle(.tertiary))
        }
        .frame(width: size.width, height: size.height)
        .offset(x: origin.x, y: origin.y)
    }

    @ViewBuilder
    private func label(_ zone: GestureZone) -> some View {
        switch zone {
        case .tracks:
            HStack(spacing: 4) {
                Image(systemName: "backward.end.fill")
                Text("Tracks")
                Image(systemName: "forward.end.fill")
            }
            .font(.system(size: 10, weight: .medium))
        case .volume, .brightness:
            VStack(spacing: 3) {
                Image(systemName: "chevron.up")
                Image(systemName: AppSymbol.icon(for: zone))
                Image(systemName: "chevron.down")
            }
            .font(.system(size: 9, weight: .semibold))
        case .mute:
            Image(systemName: AppSymbol.icon(for: zone))
                .font(.system(size: 9, weight: .semibold))
        }
    }
}

// MARK: - Status line

/// "Ready", or the one problem that matters most, with a fix button.
struct StatusLine: View {
    @Bindable var state: AppState

    private struct Problem {
        let text: String
        let fixTitle: String?
        let fix: () -> Void
        var isWarning = true
    }

    /// Ordered from most to least important. Only the first one shows.
    private var problem: Problem? {
        if !state.enabled {
            return Problem(text: "Gestures are off", fixTitle: "Turn on", fix: { state.enabled = true }, isWarning: false)
        }
        if !state.trackpadOK {
            return Problem(text: "No trackpad found", fixTitle: "Rescan") {
                state.startMonitor(); state.refreshStatus()
            }
        }
        if state.mediaEnabled && !state.mediaKeysAllowed {
            return Problem(text: "Track gestures need Accessibility", fixTitle: "Allow media keys") {
                state.requestMediaKeyAccess()
            }
        }
        if state.brightnessEnabled && !state.brightnessOK {
            return Problem(text: "Brightness is unavailable", fixTitle: "Recheck") { state.refreshStatus() }
        }
        if (state.volumeEnabled || state.muteEnabled) && !state.volumeOK {
            return Problem(text: "Volume is unavailable on this output", fixTitle: "Recheck") { state.refreshStatus() }
        }
        if state.loginNeedsApproval {
            return Problem(text: "Launch at login needs approval", fixTitle: "Open Login Items") {
                state.openLoginItemsSettings()
            }
        }
        if let error = state.lastError {
            return Problem(text: error, fixTitle: "Dismiss") { state.clearLastError() }
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 8) {
            if let problem {
                Image(systemName: problem.isWarning ? "exclamationmark.triangle.fill" : "pause.circle.fill")
                    .foregroundStyle(problem.isWarning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                Text(problem.text)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(problem.text)
                Spacer(minLength: 4)
                if let title = problem.fixTitle {
                    Button(title, action: problem.fix)
                        .controlSize(.small)
                }
            } else {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("Ready")
                Spacer(minLength: 4)
                if let action = state.lastAction {
                    Text(action)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .font(.callout)
        .frame(minHeight: 22)
    }
}
