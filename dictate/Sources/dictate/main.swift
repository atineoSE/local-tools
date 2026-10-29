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
    if options.speakers {
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
