import Foundation

/// A sentence of the final text and when it starts in the audio, in seconds.
public struct TimedSentence: Equatable, Sendable {
    public var start: Double
    public var text: String

    public init(start: Double, text: String) {
        self.start = start
        self.text = text
    }
}

public enum Timestamps {
    /// The transcript as heard: the pieces' text joined, as `Transcribe.file` would return it.
    public static func rawText(_ pieces: [TimedText]) -> String {
        pieces.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits `text` (the cleaned, or raw, transcript) into sentences and gives each the start time
    /// of its first word that matches a heard word. Names replacement and clean-up mostly delete
    /// words and change punctuation and capitals, so the final words are close to a subsequence of
    /// the heard words; a diff on normalized words lines them up.
    /// A sentence with no matching word starts right after the last matched word before it.
    /// `matched` is the share of final words that found a heard word (low after a free rewrite).
    public static func align(_ text: String, to pieces: [TimedText]) -> (sentences: [TimedSentence], matched: Double) {
        // Heard words, each with the start of the piece it came from.
        var heard: [(word: String, start: Double)] = []
        for piece in pieces {
            for word in Cleanup.words(piece.text) { heard.append((word, piece.start)) }
        }
        let sentences = text.components(separatedBy: "\n")
            .flatMap { Cleanup.sentences($0.trimmingCharacters(in: .whitespaces)) }
        let sentenceWords = sentences.map(Cleanup.words)
        let final = sentenceWords.flatMap { $0 }

        // For each final word, the index of the heard word it matches, if any.
        let diff = final.difference(from: heard.map(\.word))
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var match = [Int?](repeating: nil, count: final.count)
        var h = 0
        for f in final.indices where !inserted.contains(f) {
            while removed.contains(h) { h += 1 }
            match[f] = h
            h += 1
        }

        var result: [TimedSentence] = []
        var next = 0      // first final word of the current sentence
        var lastHeard = -1 // last heard word matched so far
        for (sentence, words) in zip(sentences, sentenceWords) {
            let range = next..<(next + words.count)
            next = range.upperBound
            let first = range.lazy.compactMap { match[$0] }.first
            let index = first ?? min(lastHeard + 1, heard.count - 1)
            let start = index >= 0 ? heard[index].start : (pieces.first?.start ?? 0)
            // Keep times in order even if a rewrite moved words around.
            result.append(TimedSentence(start: max(start, result.last?.start ?? 0), text: sentence))
            if let last = range.reversed().lazy.compactMap({ match[$0] }).first { lastHeard = last }
        }
        let matched = final.isEmpty ? 1 : Double(match.compactMap { $0 }.count) / Double(final.count)
        return (result, matched)
    }

    /// `[HH:MM:SS]`, rounded down to the second.
    public static func stamp(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "[%02d:%02d:%02d]", s / 3600, s / 60 % 60, s % 60)
    }

    /// One sentence per line, each with its stamp.
    public static func format(_ sentences: [TimedSentence]) -> String {
        sentences.map { "\(stamp($0.start)) \($0.text)" }.joined(separator: "\n")
    }

    /// Turns separated by blank lines; the speaker label follows the stamp on a turn's first line.
    public static func format(_ turns: [(speaker: Int, sentences: [TimedSentence])]) -> String {
        turns.map { turn in
            turn.sentences.enumerated().map { i, s in
                i == 0 ? "\(stamp(s.start)) Speaker \(turn.speaker): \(s.text)" : "\(stamp(s.start)) \(s.text)"
            }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    /// Below this share of matched words, the times are only rough and a warning says so.
    public static let roughBelow = 0.5
}
