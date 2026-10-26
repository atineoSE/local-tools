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
    let raw = try await Transcribe.file(url, language: options.language)
    print(await process(raw, options: options))
} catch {
    printError("dictate: \(error)")
    exit(1)
}
