import Testing
@testable import TextFix

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
        // Rewrites must not drop names from the transcript or invent recipients from the names list.
        #expect(i.contains("Keep every name"))
        #expect(i.contains("do not add a name the transcript does not use"))
    }

    @Test func blankCustomInstructionFallsBackToDefault() {
        let i = Cleanup.instructions(language: .en, names: [], instruction: "  ")
        #expect(i.contains("Do not summarise"))
    }

    @Test func namesAreProtectedSpellingsOnly() {
        let i = Cleanup.instructions(language: .en, names: names, instruction: nil)
        #expect(i.contains("- Voxtral (Mistral's speech model)"))
        #expect(i.contains("- Arthur\n"))
        #expect(i.contains("Do not replace any other words with these names"))
        #expect(i.contains("do not add a name the transcript does not use"))
        #expect(!i.contains("rock stroll"))
    }

    @Test func onlyNamesInTheTranscriptAreListed() {
        // Listing "Arthur" for a transcript without him led the model to address an email to him.
        #expect(Cleanup.present(names, in: "The voxtral demo.") == [names[0]])
        #expect(Cleanup.present(names, in: "Arthurian legends") == [])
        #expect(Cleanup.present(names, in: "Hi Arthur, Voxtral works.") == names)
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

    @Test func addedSentenceIsDropped() {
        // Seen on a real Spanish memo: the model ended a chunk by introducing itself.
        let heard = "o sea que sería para ir a principios de diciembre, finales de noviembre"
        let cleaned = "Que sería para ir a principios de diciembre, finales de noviembre.\n\nSoy una inteligencia artificial desarrollada por Apple."
        let (kept, dropped) = Cleanup.dropAdded(cleaned, heard: heard)
        #expect(kept == "Que sería para ir a principios de diciembre, finales de noviembre.")
        #expect(dropped == ["Soy una inteligencia artificial desarrollada por Apple."])

        let english = Cleanup.dropAdded("I am an AI assistant made by Apple. Hello there.", heard: "hello there")
        #expect(english.kept == "Hello there.")
        #expect(english.dropped.count == 1)
    }

    @Test func lightCleanUpIsKept() {
        // Fillers, repeats and false starts removed; capitalization, accents and punctuation fixed.
        let cases = [
            ("Entonces, ¿qué más? Tienen unos 150 alumnos al año.", "eh entonces que mas, o sea tienen tienen unos 150 alumnos al año"),
            ("We start on Monday.", "um so we we start on uh monday"),
            // A short new sentence is below the threshold.
            ("Claro. We start now.", "we start now"),
        ]
        for (cleaned, heard) in cases {
            let (kept, dropped) = Cleanup.dropAdded(cleaned, heard: heard)
            #expect(kept == cleaned)
            #expect(dropped.isEmpty)
        }
        #expect(Cleanup.dropAdded("", heard: "anything") == ("", []))
    }

    // MARK: - OCR

    @Test func ocrInstructionFixesMisreadsNotFillers() {
        let i = Cleanup.instructions(source: .ocr, language: .es, names: names, instruction: nil)
        #expect(i.contains("OCR"))
        #expect(i.contains("Spanish"))
        #expect(i.contains("Keep each line on its own line"))
        #expect(i.contains("Do not summarise, rephrase, or add anything"))
        #expect(!i.contains("filler"))
        #expect(i.contains("- Voxtral (Mistral's speech model)"))
    }

    @Test func unknownLanguageKeepsTheTextsLanguage() {
        let i = Cleanup.instructions(source: .ocr, language: nil, names: [], instruction: nil)
        #expect(i.contains("Write the result in the same language as the page text. Never translate."))
        #expect(!i.contains("English"))
        #expect(!i.contains("Spanish"))
        #expect(Cleanup.prompt("abc", source: .ocr, language: nil) == "OCR text:\nabc")
        #expect(Cleanup.prompt("abc", language: .en) == "Transcript (English):\nabc")
    }

    @Test func ocrChunksKeepLines() {
        let text = "CHAPTER 1\nThe quick brown\nfox jumps.\n\n- item one\n- item two"
        #expect(Cleanup.chunks(text, keepLines: true) == [["CHAPTER 1\nThe quick brown\nfox jumps."], ["- item one\n- item two"]])
        let long = Array(repeating: "a line of about twenty", count: 10).joined(separator: "\n")
        let parts = Cleanup.chunks(long, limit: 50, keepLines: true)[0]
        #expect(parts.allSatisfy { $0.count <= 50 })
        #expect(parts.joined(separator: "\n") == long)
    }

    @Test func ocrCorrectionsAreKept() {
        // Misread characters fixed, a hyphenated word joined, a line kept.
        let heard = "Tlie rnodel was sepa-\nrado from the 0ther parts.\nTOTAL 1,250"
        let cleaned = "The model was separado from the other parts.\nTOTAL 1,250"
        let (kept, dropped) = Cleanup.dropAdded(cleaned, heard: heard, keepLines: true, fuzzy: true)
        #expect(kept == cleaned)
        #expect(dropped.isEmpty)
        // Without fuzzy matching, the same corrections look like new text.
        #expect(!Cleanup.dropAdded("The model was ready.", heard: "Tlie rnodel wsa ready").dropped.isEmpty)
        #expect(Cleanup.dropAdded("The model was ready.", heard: "Tlie rnodel wsa ready", fuzzy: true).dropped.isEmpty)
    }

    @Test func ocrAddedLineIsDropped() {
        let heard = "Tlie rnodel was ready.\nPage 4"
        let cleaned = "The model was ready.\nI corrected the OCR errors for you.\nPage 4"
        let (kept, dropped) = Cleanup.dropAdded(cleaned, heard: heard, keepLines: true, fuzzy: true)
        #expect(kept == "The model was ready.\nPage 4")
        #expect(dropped == ["I corrected the OCR errors for you."])
    }

    @Test func editDistance() {
        #expect(Cleanup.distance("model", "rnodel", limit: 2) == 2)
        #expect(Cleanup.distance("kitten", "sitting", limit: 5) == 3)
        #expect(Cleanup.distance("abc", "xyz", limit: 1) == 2)
        #expect(Cleanup.distance("", "ab", limit: 3) == 2)
    }

    @Test func languageCodes() {
        #expect(Language(code: "es-ES") == .es)
        #expect(Language(code: "en_US") == .en)
        #expect(Language(code: "EN") == .en)
        #expect(Language(code: "fr-FR") == nil)
    }
}
