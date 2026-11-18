import Foundation

/// A language the clean-up has specific instructions for.
public enum Language: String, Sendable, CaseIterable {
    case en, es

    /// Matches a language code with or without a region: "es", "es-ES", "es_MX", "EN-us".
    public init?(code: String) {
        let base = code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { $0.lowercased() } ?? ""
        self.init(rawValue: base)
    }

    /// The English name of the language, as used in the model instructions.
    public var name: String {
        switch self {
        case .en: "English"
        case .es: "Spanish"
        }
    }
}
