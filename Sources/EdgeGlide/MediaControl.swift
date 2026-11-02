import AppKit
import CoreGraphics
import Foundation

enum MediaError: LocalizedError {
    case noMethod(String)
    case postEventNotAllowed

    var errorDescription: String? {
        switch self {
        case .noMethod(let reason): "No way to send media commands: \(reason)"
        case .postEventNotAllowed:
            "MediaRemote failed and EdgeGlide may not post media keys. Allow it in System Settings > Privacy & Security > Accessibility"
        }
    }
}

/// Sends next and previous track commands.
///
/// It tries the private `MRMediaRemoteSendCommand` first. When that symbol is
/// missing or the call returns false, it posts the system-defined media key
/// events the keyboard sends, which needs Accessibility permission.
@MainActor
final class MediaControl {
    /// `MRMediaRemoteCommand` values from the reverse-engineered MediaRemote
    /// headers (for example the MediaRemote.h used by nowplaying-cli and
    /// MediaRemoteAdapter): play 0, pause 1, togglePlayPause 2, stop 3,
    /// nextTrack 4, previousTrack 5.
    enum Command: Int32 {
        case nextTrack = 4
        case previousTrack = 5

        /// `NX_KEYTYPE_NEXT` and `NX_KEYTYPE_PREVIOUS` from IOKit `ev_keymap.h`.
        var mediaKey: Int32 { self == .nextTrack ? 17 : 18 }
        var name: String { self == .nextTrack ? "next track" : "previous track" }
    }

    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool
    private var sendCommand: SendCommandFn?
    private(set) var loadError: Error?

    init() {
        switch PrivateFramework.open("MediaRemote") {
        case .failure(let error):
            loadError = error
            Log.media.error("\(error.localizedDescription, privacy: .public)")
        case .success(let fw):
            sendCommand = fw.symbol("MRMediaRemoteSendCommand", as: SendCommandFn.self)
            if sendCommand == nil {
                loadError = PrivateFrameworkError.symbolMissing(framework: "MediaRemote", symbol: "MRMediaRemoteSendCommand")
                Log.media.error("MRMediaRemoteSendCommand missing; media keys are the only path")
            } else {
                Log.media.notice("MRMediaRemoteSendCommand resolved")
            }
        }
    }

    /// True when the app may post synthetic keyboard events.
    var canPostEvents: Bool { CGPreflightPostEventAccess() }

    /// Shows the system prompt that lets you grant event posting access.
    func requestPostEventAccess() {
        let granted = CGRequestPostEventAccess()
        Log.media.notice("CGRequestPostEventAccess returned \(granted, privacy: .public)")
    }

    /// Returns a short description of the path that worked.
    @discardableResult
    func send(_ command: Command) throws -> String {
        if let sendCommand {
            if sendCommand(command.rawValue, nil) {
                Log.media.info("MRMediaRemoteSendCommand(\(command.rawValue, privacy: .public)) succeeded")
                return "MediaRemote"
            }
            Log.media.error("MRMediaRemoteSendCommand(\(command.rawValue, privacy: .public)) returned false; trying media key")
        }
        guard canPostEvents else { throw MediaError.postEventNotAllowed }
        postMediaKey(command.mediaKey)
        Log.media.info("Posted media key \(command.mediaKey, privacy: .public) for \(command.name, privacy: .public)")
        return "media key"
    }

    private func postMediaKey(_ key: Int32) {
        for down in [true, false] {
            let state: Int32 = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: Int((key << 16) | (state << 8)),
                data2: -1)
            guard let cgEvent = event?.cgEvent else {
                Log.media.error("Could not build media key event for key \(key, privacy: .public)")
                continue
            }
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    func describe() -> String {
        let remote = sendCommand == nil ? "MediaRemote unavailable" : "MediaRemote ready"
        let keys = canPostEvents ? "media keys allowed" : "media keys need Accessibility"
        return "\(remote), \(keys)"
    }
}
