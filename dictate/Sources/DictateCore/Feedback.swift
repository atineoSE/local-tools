import AppKit
import Foundation

public enum Cue: Sendable {
    case start, stop, ready

    var soundName: String {
        switch self {
        case .start: "Tink"
        case .stop: "Pop"
        case .ready: "Glass"
        }
    }
}

public enum Feedback {
    /// Plays a cue sound and returns after it finishes. A missing sound file is skipped silently.
    public static func play(_ cue: Cue) {
        let path = "/System/Library/Sounds/\(cue.soundName).aiff"
        guard FileManager.default.fileExists(atPath: path),
              let sound = NSSound(contentsOfFile: path, byReference: true),
              sound.play()
        else { return }
        // Poll, spinning the run loop so NSSound can update its state; a command-line tool
        // has no running run loop of its own. The deadline guards against a sound that
        // never reports finishing.
        let deadline = Date().addingTimeInterval(sound.duration + 0.5)
        while sound.isPlaying, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// Copies text to the clipboard.
    public static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Surfaces an error to the user as a macOS notification. Never throws.
    public static func notifyError(_ message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", notificationScript(message)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {}
    }

    static func notificationScript(_ message: String) -> String {
        "display notification \(appleScriptString(message)) with title \"dictate\""
    }

    static func appleScriptString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
