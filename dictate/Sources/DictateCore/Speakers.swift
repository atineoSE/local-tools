import FluidAudio
import Foundation

/// A run of transcribed text and where it sits in the audio, in seconds.
public struct TimedText: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// A stretch of audio the diarizer gave to one speaker.
public struct SpeakerSpan: Equatable, Sendable {
    public var speaker: String
    public var start: Double
    public var end: Double

    public init(speaker: String, start: Double, end: Double) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

/// Consecutive text by one speaker. Speakers are numbered from 1 in order of first appearance.
public struct Turn: Equatable, Sendable {
    public var speaker: Int
    public var text: String

    public init(speaker: Int, text: String) {
        self.speaker = speaker
        self.text = text
    }
}

public enum Speakers {
    /// Who spoke when, with FluidAudio's offline (pyannote + VBx) pipeline. Downloads the models on first use.
    /// `count` forces the number of speakers; nil lets the clustering decide.
    public static func diarize(_ url: URL, count: Int?) async throws -> [SpeakerSpan] {
        // FluidAudio logs every step at info level; keep stderr for dictate's own messages.
        AppLogger.minimumLevel = .warning
        var config = OfflineDiarizerConfig()
        config.clustering.numSpeakers = count
        let manager = OfflineDiarizerManager(config: config)
        let cache = OfflineDiarizerModels.defaultModelsDirectory().appendingPathComponent(Repo.diarizer.folderName)
        if !FileManager.default.fileExists(atPath: cache.path) {
            printError("Downloading on-device speaker models…")
        }
        try await manager.prepareModels()
        let result = try await manager.process(url)
        return result.segments.map {
            SpeakerSpan(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
        }
    }

    /// Gives each piece of text to the speaker whose span overlaps it most (or the nearest span when
    /// none overlaps), then merges neighbours with the same speaker. Whitespace-only pieces stay with
    /// the previous speaker. No spans at all → one turn by speaker 1.
    public static func turns(_ pieces: [TimedText], spans: [SpeakerSpan]) -> [Turn] {
        var numbers: [String: Int] = [:]
        var turns: [Turn] = []
        for piece in pieces {
            let isBlank = piece.text.allSatisfy(\.isWhitespace)
            let speaker: Int
            if isBlank, let last = turns.last {
                speaker = last.speaker
            } else if let id = bestSpeaker(for: piece, in: spans) {
                if numbers[id] == nil { numbers[id] = numbers.count + 1 }
                speaker = numbers[id]!
            } else {
                speaker = turns.last?.speaker ?? 1
            }
            if turns.last?.speaker == speaker {
                turns[turns.count - 1].text += piece.text
            } else {
                turns.append(Turn(speaker: speaker, text: piece.text))
            }
        }
        return turns.compactMap {
            let text = $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : Turn(speaker: $0.speaker, text: text)
        }
    }

    static func bestSpeaker(for piece: TimedText, in spans: [SpeakerSpan]) -> String? {
        var best: (id: String, overlap: Double)?
        for span in spans {
            let overlap = min(piece.end, span.end) - max(piece.start, span.start)
            if overlap > 0, overlap > (best?.overlap ?? 0) { best = (span.speaker, overlap) }
        }
        if let best { return best.id }
        let middle = (piece.start + piece.end) / 2
        return spans.min { distance(middle, $0) < distance(middle, $1) }?.speaker
    }

    static func distance(_ time: Double, _ span: SpeakerSpan) -> Double {
        time < span.start ? span.start - time : max(0, time - span.end)
    }

    /// "Speaker 1: …" paragraphs separated by blank lines.
    public static func format(_ turns: [Turn]) -> String {
        turns.map { "Speaker \($0.speaker): \($0.text)" }.joined(separator: "\n\n")
    }
}
