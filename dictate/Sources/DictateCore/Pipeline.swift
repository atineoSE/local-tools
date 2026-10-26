import Foundation

/// raw → returned as is. Otherwise: names = Names.load(path: options.namesPath.map(URL.init(fileURLWithPath:)) ?? Names.defaultPath()),
/// then Names.apply, then Cleanup.run(…, instruction: options.instruct). A names-file load error → warning on stderr, continue with no names.
public func process(_ raw: String, options: Options) async -> String {
    if options.raw { return raw }
    let path = options.namesPath.map(URL.init(fileURLWithPath:)) ?? Names.defaultPath()
    let names: [NameEntry]
    do {
        names = try Names.load(path: path)
    } catch {
        printError("warning: could not load names file\(path.map { " \($0.path)" } ?? ""): \(error)")
        names = []
    }
    let named = Names.apply(names, to: raw)
    return await Cleanup.run(named, language: options.language, names: names, instruction: options.instruct)
}
