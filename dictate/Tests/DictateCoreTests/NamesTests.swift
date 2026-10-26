import Foundation
import Testing
@testable import DictateCore

@Suite struct NamesTests {
    @Test func parsesExampleFormat() {
        let entries = Names.parse("""
            # comment lines and blank lines are ignored

              # indented comment
            Voxtral, Mistral's speech model, heard: rock stroll | box trawl | foxtraw
            Mistral, AI company from Paris, heard: miss trail | mostral
            Arthur
            """)
        #expect(entries == [
            NameEntry(name: "Voxtral", context: "Mistral's speech model", heardAs: ["rock stroll", "box trawl", "foxtraw"]),
            NameEntry(name: "Mistral", context: "AI company from Paris", heardAs: ["miss trail", "mostral"]),
            NameEntry(name: "Arthur", context: "", heardAs: []),
        ])
    }

    @Test func contextWithCommas() {
        let e = Names.parseLine("Ana, my sister, lives in Madrid, likes tea, HEARD: anna | Ana na |  | ")
        #expect(e == NameEntry(name: "Ana", context: "my sister, lives in Madrid, likes tea", heardAs: ["anna", "Ana na"]))
    }

    @Test func heardWithoutContext() {
        #expect(Names.parseLine("Voxtral, heard: rock stroll") == NameEntry(name: "Voxtral", context: "", heardAs: ["rock stroll"]))
        #expect(Names.parseLine("Voxtral,") == NameEntry(name: "Voxtral", context: "", heardAs: []))
        #expect(Names.parseLine("Arthur, a colleague") == NameEntry(name: "Arthur", context: "a colleague", heardAs: []))
    }

    @Test func heardListMayContainCommas() {
        let e = Names.parseLine("Foo, ctx, heard: a, b | c")
        #expect(e?.heardAs == ["a, b", "c"])
    }

    @Test func missingNameIsSkipped() {
        #expect(Names.parseLine(", context only") == nil)
        #expect(Names.parseLine("   ") == nil)
    }

    @Test func replacesCaseInsensitiveWholeWord() {
        let names = [NameEntry(name: "Mistral", context: "", heardAs: ["miss trail", "mostral"])]
        #expect(Names.apply(names, to: "The Miss Trail team, and MOSTRAL.") == "The Mistral team, and Mistral.")
        #expect(Names.apply(names, to: "mostrals and amostral stay") == "mostrals and amostral stay")
        #expect(Names.apply(names, to: "(miss  trail)!") == "(Mistral)!")
    }

    @Test func accentedCharacters() {
        let names = [NameEntry(name: "Begoña", context: "", heardAs: ["vegoña", "bego ña"])]
        #expect(Names.apply(names, to: "Hola VEGOÑA, ¿qué tal?") == "Hola Begoña, ¿qué tal?")
        #expect(Names.apply(names, to: "vegoñaé") == "vegoñaé")
        let es = [NameEntry(name: "José", context: "", heardAs: ["jose"])]
        #expect(Names.apply(es, to: "josé y jose") == "josé y José")
    }

    @Test func longestVariantFirst() {
        let names = [
            NameEntry(name: "Rock", context: "", heardAs: ["rock"]),
            NameEntry(name: "Voxtral", context: "", heardAs: ["rock stroll"]),
        ]
        #expect(Names.apply(names, to: "the rock stroll demo, rock on") == "the Voxtral demo, Rock on")
    }

    @Test func noEntriesLeavesText() {
        #expect(Names.apply([], to: "unchanged") == "unchanged")
    }

    @Test func loadMissingOrNil() throws {
        #expect(try Names.load(path: nil) == [])
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID()).txt")
        #expect(try Names.load(path: missing) == [])
    }

    @Test func loadFileAndUnreadable() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("names.txt")
        try "# c\nVoxtral, model, heard: rock stroll\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(try Names.load(path: file) == [NameEntry(name: "Voxtral", context: "model", heardAs: ["rock stroll"])])
        // A directory exists but cannot be read as text.
        #expect(throws: (any Error).self) { try Names.load(path: dir) }
    }

    @Test func repoRootResolvesSymlink() throws {
        let fm = FileManager.default
        let dir = try makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        let repo = dir.appendingPathComponent("repo")
        let build = repo.appendingPathComponent("dictate/.build/release")
        try fm.createDirectory(at: build, withIntermediateDirectories: true)
        try "".write(to: repo.appendingPathComponent("dictate/Package.swift"), atomically: true, encoding: .utf8)
        let exe = build.appendingPathComponent("dictate")
        try "".write(to: exe, atomically: true, encoding: .utf8)
        let bin = dir.appendingPathComponent("bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let link = bin.appendingPathComponent("dictate")
        try fm.createSymbolicLink(at: link, withDestinationURL: exe)

        let expected = repo.resolvingSymlinksInPath().standardizedFileURL.path
        #expect(Names.repoRoot(fromExecutable: link)?.standardizedFileURL.path.hasSuffix("/repo") == true)
        #expect(Names.repoRoot(fromExecutable: link)?.resolvingSymlinksInPath().path == expected)
        #expect(Names.repoRoot(fromExecutable: exe)?.resolvingSymlinksInPath().path == expected)
        // The installed command is a symlink (e.g. ~/.local/bin/dictate); its default names file is the repo's.
        let names = Names.defaultPath(executable: link)
        #expect(names?.lastPathComponent == "names.txt")
        #expect(names?.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath().path == expected)
        // Without the package marker, nothing is found.
        try fm.removeItem(at: repo.appendingPathComponent("dictate/Package.swift"))
        #expect(Names.repoRoot(fromExecutable: link) == nil)
    }

    @Test func defaultPathFindsThisRepo() {
        // The test binary lives under dictate/.build, so the default resolves to <repo>/dictate/names.txt.
        guard let path = Names.defaultPath() else { return }
        #expect(path.lastPathComponent == "names.txt")
        #expect(FileManager.default.fileExists(atPath: path.deletingLastPathComponent().appendingPathComponent("Package.swift").path))
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("names-tests-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
