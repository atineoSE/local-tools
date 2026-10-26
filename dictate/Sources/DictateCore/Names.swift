import Foundation

public struct NameEntry: Equatable, Sendable {
    public let name: String
    public let context: String
    public let heardAs: [String]

    public init(name: String, context: String, heardAs: [String]) {
        self.name = name
        self.context = context
        self.heardAs = heardAs
    }
}

public enum Names {
    /// Default names file location. Stub: no default yet.
    public static func defaultPath() -> URL? {
        nil
    }

    /// Loads name entries from `path`. Stub: no names.
    public static func load(path: URL?) throws -> [NameEntry] {
        []
    }

    /// Replaces mis-heard spellings with the correct names. Stub: text unchanged.
    public static func apply(_ entries: [NameEntry], to text: String) -> String {
        text
    }
}
