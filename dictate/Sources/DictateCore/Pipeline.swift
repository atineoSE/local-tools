import Foundation

/// raw → returned as is. Otherwise: names = Names.load(path: options.namesPath.map(URL.init(fileURLWithPath:)) ?? Names.defaultPath()),
/// then Names.apply, then Cleanup.run(…, instruction: options.instruct). A names-file load error → warning on stderr, continue with no names.
/// `turn` (number from 1, number of turns) is shown in the status line when turns are cleaned up one by one.
public func process(_ raw: String, options: Options, turn: (Int, Int)? = nil) async -> String {
    if options.raw { return raw }
    let path = options.namesPath.map(URL.init(fileURLWithPath:)) ?? Names.defaultPath()
    if let explicit = options.namesPath, !FileManager.default.fileExists(atPath: explicit) {
        printError("warning: names file \(explicit) not found; names not replaced")
    }
    let names: [NameEntry]
    do {
        names = try Names.load(path: path)
    } catch {
        printError("warning: could not load names file\(path.map { " \($0.path)" } ?? ""): \(error)")
        names = []
    }
    let named = Names.apply(names, to: raw)
    let stage = "Cleaning up"
    defer { Status.shared.done(stage) }
    return await Cleanup.run(named, language: options.language, names: names, instruction: options.instruct) { number, total in
        Status.shared.set(stage, text: cleanupDetail(turn: turn, chunk: (number, total)))
    }
}

/// "turn 2/5, part 1/3"; each count only when there is more than one.
func cleanupDetail(turn: (Int, Int)?, chunk: (Int, Int)) -> String {
    var parts: [String] = []
    if let turn, turn.1 > 1 { parts.append("turn \(turn.0)/\(turn.1)") }
    if chunk.1 > 1 { parts.append("part \(chunk.0)/\(chunk.1)") }
    return parts.joined(separator: ", ")
}
