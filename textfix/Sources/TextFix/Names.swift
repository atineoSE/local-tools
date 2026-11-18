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

/// A names file: known names, and the ways a recogniser (speech or OCR) gets them wrong.
public enum Names {
    /// The words that start the misrecognition list: `heard:` (speech) or `seen:` (OCR); they mean the same.
    static let variantKeys = ["heard:", "seen:"]

    /// `<repo>/<tool>/names.txt`, where `<repo>` is the nearest ancestor of the running executable's
    /// real path (symlinks resolved) that contains `<tool>/Package.swift`. `nil` if not found.
    public static func defaultPath(tool: String, executable: URL? = Bundle.main.executableURL) -> URL? {
        guard let exe = executable else { return nil }
        return repoRoot(fromExecutable: exe, tool: tool)?.appendingPathComponent("\(tool)/names.txt")
    }

    /// Loads the names file for a tool: `explicit` if given (a missing explicit file is reported through `warn`),
    /// else the tool's default. Load errors are reported through `warn` and give no names.
    public static func load(explicit: String?, tool: String, warn: (String) -> Void) -> [NameEntry] {
        let path = explicit.map(URL.init(fileURLWithPath:)) ?? defaultPath(tool: tool)
        if let explicit, !FileManager.default.fileExists(atPath: explicit) {
            warn("warning: names file \(explicit) not found; names not replaced")
        }
        do {
            return try load(path: path)
        } catch {
            warn("warning: could not load names file\(path.map { " \($0.path)" } ?? ""): \(error)")
            return []
        }
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
        func key(_ field: String) -> String? {
            let f = field.trimmingCharacters(in: .whitespaces).lowercased()
            return variantKeys.first(where: f.hasPrefix)
        }
        let heardIndex = rest.firstIndex { key($0) != nil }
        let contextFields = rest[..<(heardIndex ?? rest.endIndex)]
        let context = contextFields.joined(separator: ",").trimmingCharacters(in: .whitespaces)

        var heardAs: [String] = []
        if let heardIndex {
            let heard = rest[heardIndex...].joined(separator: ",").trimmingCharacters(in: .whitespaces)
            heardAs = heard.dropFirst(key(heard)!.count)
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return NameEntry(name: name, context: context, heardAs: heardAs)
    }

    /// Walks up from the executable's real path to the directory containing `<tool>/Package.swift`.
    static func repoRoot(fromExecutable exe: URL, tool: String) -> URL? {
        guard let real = realpath(exe.path, nil) else { return nil }
        defer { free(real) }
        var dir = URL(fileURLWithPath: String(cString: real)).deletingLastPathComponent()
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: dir.appendingPathComponent("\(tool)/Package.swift").path) { return dir }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }
}
