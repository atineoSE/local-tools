import DictateCore
import Foundation

let options: Options
do {
    options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
} catch .help {
    print(Options.usage)
    exit(0)
} catch .invalid(let message) {
    printError("dictate: \(message)\n\n\(Options.usage)")
    exit(2)
}

if options.live {
    exit(await Live.run(options: options))
}

do {
    let url = URL(fileURLWithPath: options.file!)
    guard FileManager.default.fileExists(atPath: url.path) else {
        printError("dictate: no such file: \(url.path)")
        exit(1)
    }
    if options.timestamps {
        // Clean up the text as heard, then match its words back to the heard words for their times.
        async let timed = Transcribe.timedFile(url, language: options.language)
        let spans = options.speakers ? try await Speakers.diarize(url, count: options.speakerCount) : []
        let pieces = try await timed
        let groups = options.speakers ? Speakers.groups(pieces, spans: spans) : [(speaker: 1, pieces: pieces)]
        var turns: [(speaker: Int, sentences: [TimedSentence])] = []
        var rough = false
        for group in groups {
            let text = await process(Timestamps.rawText(group.pieces), options: options)
            let (sentences, matched) = Timestamps.align(text, to: group.pieces)
            rough = rough || matched < Timestamps.roughBelow
            if !sentences.isEmpty { turns.append((group.speaker, sentences)) }
        }
        if rough {
            printError("warning: the cleaned-up text differs a lot from what was said; timestamps are approximate")
        }
        print(options.speakers ? Timestamps.format(turns) : Timestamps.format(turns.flatMap(\.sentences)))
    } else if options.speakers {
        async let pieces = Transcribe.timedFile(url, language: options.language)
        async let spans = Speakers.diarize(url, count: options.speakerCount)
        var turns = Speakers.turns(try await pieces, spans: try await spans)
        // Names and clean-up per turn, so the model never sees (or rewrites) the speaker labels.
        for i in turns.indices {
            turns[i].text = await process(turns[i].text, options: options)
        }
        print(Speakers.format(turns))
    } else {
        let raw = try await Transcribe.file(url, language: options.language)
        print(await process(raw, options: options))
    }
} catch {
    printError("dictate: \(error)")
    exit(1)
}
