import Foundation

public enum Cue: Sendable {
    case start, stop, ready
}

public enum Feedback {
    /// Plays a cue sound and returns after it finishes. Stub: does nothing.
    public static func play(_ cue: Cue) {}

    /// Copies text to the clipboard. Stub: does nothing.
    public static func copyToClipboard(_ text: String) {}

    /// Surfaces an error to the user. Stub: does nothing.
    public static func notifyError(_ message: String) {}
}
