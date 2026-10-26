import Testing
@testable import DictateCore

@Suite struct CleanupTests {
    let names = [
        NameEntry(name: "Voxtral", context: "Mistral's speech model", heardAs: ["rock stroll"]),
        NameEntry(name: "Arthur", context: "", heardAs: []),
    ]

    @Test func defaultInstructionIsLight() {
        let i = Cleanup.instructions(language: .en, names: [], instruction: nil)
        #expect(i.contains("English"))
        #expect(i.contains("\"um\""))
        #expect(i.contains("Do not summarise, rephrase, or add anything"))
        #expect(i.contains("Never translate"))
        #expect(!i.contains("names"))
        #expect(!i.lowercased().contains("improve"))
    }

    @Test func spanishInstruction() {
        let i = Cleanup.instructions(language: .es, names: [], instruction: nil)
        #expect(i.contains("Spanish"))
        #expect(i.contains("\"o sea\""))
        #expect(!i.contains("English"))
    }

    @Test func customInstructionReplacesDefaultButKeepsRules() {
        let i = Cleanup.instructions(language: .es, names: names, instruction: "make this an email")
        #expect(i.contains("make this an email"))
        #expect(!i.contains("Do not summarise"))
        #expect(i.contains("Write the result in Spanish"))
        #expect(i.contains("- Voxtral (Mistral's speech model)"))
    }

    @Test func blankCustomInstructionFallsBackToDefault() {
        let i = Cleanup.instructions(language: .en, names: [], instruction: "  ")
        #expect(i.contains("Do not summarise"))
    }

    @Test func namesAreProtectedSpellingsOnly() {
        let i = Cleanup.instructions(language: .en, names: names, instruction: nil)
        #expect(i.contains("- Voxtral (Mistral's speech model)"))
        #expect(i.contains("- Arthur\n"))
        #expect(i.contains("Do not replace any other words with these names."))
        #expect(!i.contains("rock stroll"))
    }

    @Test func shortTextIsOneChunk() {
        #expect(Cleanup.chunks("Hello there. How are you?") == [["Hello there. How are you?"]])
        #expect(Cleanup.chunks("  \n ") == [])
    }

    @Test func sentenceSplitting() {
        #expect(Cleanup.sentences("One. Two? \"Three!\" Four… five 3.5 six") ==
                ["One.", "Two?", "\"Three!\"", "Four…", "five 3.5 six"])
    }

    @Test func longTextSplitsOnSentencesWithinLimit() {
        let sentence = "This is a sentence of moderate length used for testing."  // 55 chars
        let text = Array(repeating: sentence, count: 100).joined(separator: " ")
        let chunks = Cleanup.chunks(text)
        #expect(chunks.count == 1)
        let parts = chunks[0]
        #expect(parts.count > 1)
        #expect(parts.allSatisfy { $0.count <= Cleanup.chunkLimit })
        #expect(parts.allSatisfy { $0.hasSuffix("testing.") && $0.hasPrefix("This") })
        #expect(parts.joined(separator: " ") == text)
    }

    @Test func overlongSentenceSplitsOnSpaces() {
        let text = Array(repeating: "word", count: 50).joined(separator: " ")
        let parts = Cleanup.chunks(text, limit: 40)[0]
        #expect(parts.allSatisfy { $0.count <= 40 })
        #expect(parts.joined(separator: " ") == text)
    }

    @Test func paragraphsAreKept() {
        let chunks = Cleanup.chunks("First para.\nStill first.\n\n\nSecond para.")
        #expect(chunks == [["First para. Still first."], ["Second para."]])
    }

    @Test func stripWrapping() {
        #expect(Cleanup.stripWrapping("\"Hello there.\"") == "Hello there.")
        #expect(Cleanup.stripWrapping("“Hola.”") == "Hola.")
        #expect(Cleanup.stripWrapping("Here is the cleaned text:\n\nHello there.") == "Hello there.")
        #expect(Cleanup.stripWrapping("Aquí está el texto:\nHola.") == "Hola.")
        #expect(Cleanup.stripWrapping("He said \"hi\" and \"bye\"") == "He said \"hi\" and \"bye\"")
        #expect(Cleanup.stripWrapping("\"Hi\" and \"bye\"") == "\"Hi\" and \"bye\"")
        #expect(Cleanup.stripWrapping("Here is the plan. We start now.") == "Here is the plan. We start now.")
    }
}
