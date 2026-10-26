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
    /// `<repo>/dictate/names.txt`, where `<repo>` is the nearest ancestor of the running executable's
    /// real path (symlinks resolved) that contains `dictate/Package.swift`. `nil` if not found.
    public static func defaultPath(executable: URL? = Bundle.main.executableURL) -> URL? {
        guard let exe = executable else { return nil }
        return repoRoot(fromExecutable: exe)?.appendingPathComponent("dictate/names.txt")
    }

    /// Loads name entries from `path`. `nil` or a missing file → `[]`; an unreadable file throws.
    public static func load(path: URL?) throws -> [NameEntry] {
        guard let path, FileManager.default.fileExists(atPath: path.path) else { return [] }
        return parse(try String(contentsOf: path, encoding: .utf8))
    }

    /// Replaces heard-as variants (case-insensitive, whole word, longest first) with the entry's name.
    public static func apply(_ entries: [NameEntry], to text: String) -> String {
        let pairs = entries
            .flatMap { e in e.heardAs.map { (variant: $0, name: e.name) } }
            .filter { !$0.variant.isEmpty }
            .sorted { $0.variant.count > $1.variant.count }
        guard !pairs.isEmpty else { return text }

        // One alternation, longest variant first, one capture group per variant, so a single pass
        // picks the longest match at each position and never re-replaces an inserted name.
        let alternatives = pairs.map { pair in
            "(" + pair.variant.split(whereSeparator: \.isWhitespace)
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: "\\s+") + ")"
        }
        let pattern = "(?<![\\p{L}\\p{N}_])(?:" + alternatives.joined(separator: "|") + ")(?![\\p{L}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }

        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let group = (1..<match.numberOfRanges).first(where: { match.range(at: $0).location != NSNotFound })
            else { continue }
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += pairs[group - 1].name
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    static func parse(_ contents: String) -> [NameEntry] {
        contents.components(separatedBy: .newlines).compactMap(parseLine)
    }

    static func parseLine(_ line: String) -> NameEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }

        let fields = trimmed.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let name = fields[0].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        let rest = fields.dropFirst()
        let heardIndex = rest.firstIndex {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("heard:")
        }
        let contextFields = rest[..<(heardIndex ?? rest.endIndex)]
        let context = contextFields.joined(separator: ",").trimmingCharacters(in: .whitespaces)

        var heardAs: [String] = []
        if let heardIndex {
            let heard = rest[heardIndex...].joined(separator: ",").trimmingCharacters(in: .whitespaces)
            heardAs = heard.dropFirst("heard:".count)
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return NameEntry(name: name, context: context, heardAs: heardAs)
    }

    /// Walks up from the executable's real path to the directory containing `dictate/Package.swift`.
    static func repoRoot(fromExecutable exe: URL) -> URL? {
        guard let real = realpath(exe.path, nil) else { return nil }
        defer { free(real) }
        var dir = URL(fileURLWithPath: String(cString: real)).deletingLastPathComponent()
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: dir.appendingPathComponent("dictate/Package.swift").path) { return dir }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }
}
