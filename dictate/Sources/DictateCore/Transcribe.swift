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
    public static func makeTranscriber(language: Language) async throws -> SpeechTranscriber {
        let localeID = language.localeID
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw TranscribeError.unsupportedLocale(localeID)
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            printError("Downloading on-device speech model for \(localeID)…")
            try await request.downloadAndInstall()
            printError("Speech model installed.")
        }
        return transcriber
    }

    public static func file(_ url: URL, language: Language) async throws -> String {
        let transcriber = try await makeTranscriber(language: language)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
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
}
