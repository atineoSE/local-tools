import AVFoundation
import Foundation
import Speech

public enum TranscribeError: Error, CustomStringConvertible {
    case unsupportedLocale(String)

    public var description: String {
        switch self {
        case .unsupportedLocale(let id): "speech recognition does not support locale \(id) on this Mac"
        }
    }
}

public enum Transcribe {
    /// Supported-locale check + on-device model download if missing (message to stderr while downloading).
    /// `timed` adds an audio time range to each run of text (needed to match text to speakers).
    public static func makeTranscriber(language: Language, timed: Bool = false) async throws -> SpeechTranscriber {
        let localeID = language.localeID
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw TranscribeError.unsupportedLocale(localeID)
        }
        let transcriber = timed
            ? SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
            : SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            printError("Downloading on-device speech model for \(localeID)…")
            let progress = request.progress
            Status.shared.set("Downloading speech model") { Status.percent(progress.fractionCompleted) }
            defer { Status.shared.done("Downloading speech model") }
            try await request.downloadAndInstall()
            printError("Speech model installed.")
        }
        return transcriber
    }

    /// Status stage shown while a file is transcribed.
    static let stage = "Transcribing"

    /// Shows how far into the file the transcriber has got, as a percentage of its duration.
    static func report(_ result: SpeechTranscriber.Result, duration: Double) {
        guard duration > 0 else { return }
        Status.shared.set(stage, fraction: result.range.end.seconds / duration)
    }

    static func duration(_ file: AVAudioFile) -> Double {
        Double(file.length) / file.processingFormat.sampleRate
    }

    public static func file(_ url: URL, language: Language) async throws -> String {
        let transcriber = try await makeTranscriber(language: language)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        let duration = duration(file)
        Status.shared.set(stage, fraction: 0)
        defer { Status.shared.done(stage) }
        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
                report(result, duration: duration)
            }
            return text
        }
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let text = try await collector.value
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Like `file`, but keeps each run of text with its position in the audio.
    /// A run without a time range takes the range of the result it belongs to.
    public static func timedFile(_ url: URL, language: Language) async throws -> [TimedText] {
        let transcriber = try await makeTranscriber(language: language, timed: true)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        let duration = duration(file)
        Status.shared.set(stage, fraction: 0)
        defer { Status.shared.done(stage) }
        let collector = Task {
            var pieces: [TimedText] = []
            for try await result in transcriber.results where result.isFinal {
                for run in result.text.runs {
                    let range = run.audioTimeRange ?? result.range
                    pieces.append(TimedText(
                        text: String(result.text[run.range].characters),
                        start: range.start.seconds,
                        end: range.end.seconds
                    ))
                }
                report(result, duration: duration)
            }
            return pieces
        }
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collector.value
    }
}
