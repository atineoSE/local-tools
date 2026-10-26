import Testing
@testable import DictateCore

@Suite struct OptionsTests {
    @Test func fileWithDefaults() throws {
        let o = try Options.parse(["a.m4a"])
        #expect(o == Options(file: "a.m4a"))
        #expect(o.language == .en)
        #expect(!o.live && !o.raw)
    }

    @Test func allFileFlags() throws {
        let o = try Options.parse(["--raw", "--language", "es", "--instruct", "make this an email", "--names", "n.md", "x.wav"])
        #expect(o == Options(file: "x.wav", language: .es, raw: true, instruct: "make this an email", namesPath: "n.md"))
    }

    @Test func inlineValues() throws {
        let o = try Options.parse(["--language=es", "--names=n.md", "x.wav"])
        #expect(o.language == .es)
        #expect(o.namesPath == "n.md")
    }

    @Test func live() throws {
        let o = try Options.parse(["--live", "--language", "es"])
        #expect(o.live && o.file == nil && o.language == .es)
    }

    @Test func simulateMicImpliesLive() throws {
        let o = try Options.parse(["--simulate-mic", "f.m4a"])
        #expect(o.live)
        #expect(o.simulateMic == "f.m4a")
        #expect(o.file == nil)
    }

    @Test func dashDashEndsFlags() throws {
        #expect(try Options.parse(["--", "--weird.m4a"]).file == "--weird.m4a")
    }

    @Test func help() {
        #expect(throws: OptionsError.help) { try Options.parse(["-h"]) }
        #expect(throws: OptionsError.help) { try Options.parse(["x.m4a", "--help"]) }
    }

    @Test(arguments: [
        [String](),                        // no FILE and no --live
        ["--live", "x.m4a"],               // both
        ["--simulate-mic", "s.m4a", "x.m4a"],
        ["a.m4a", "b.m4a"],                // two files
        ["--language", "fr", "x.m4a"],     // unsupported language
        ["x.m4a", "--language"],           // missing value
        ["--names"],
        ["--bogus", "x.m4a"],
        ["--raw=yes", "x.m4a"],
    ])
    func invalid(_ args: [String]) {
        #expect {
            try Options.parse(args)
        } throws: { error in
            if case .invalid = error as? OptionsError { return true }
            return false
        }
    }

    @Test func localeIDs() {
        #expect(Language.en.localeID == "en-US")
        #expect(Language.es.localeID == "es-ES")
    }
}

@Suite struct PipelineTests {
    @Test func rawSkipsEverything() async {
        let text = "So, um, hello"
        #expect(await process(text, options: Options(file: "x", raw: true)) == text)
    }

    @Test func stubPipelineLeavesTextUnchanged() async {
        #expect(await process("hello", options: Options(file: "x")) == "hello")
    }
}
