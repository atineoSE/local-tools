import Testing
@testable import DictateCore

@Suite struct SpeakersTests {
    let spans = [
        SpeakerSpan(speaker: "S7", start: 0, end: 2),
        SpeakerSpan(speaker: "S3", start: 2, end: 4),
        SpeakerSpan(speaker: "S7", start: 4, end: 6),
    ]

    @Test func assignsByOverlapAndNumbersByFirstAppearance() {
        let pieces = [
            TimedText(text: "Hello ", start: 0.1, end: 0.8),
            TimedText(text: "there. ", start: 0.8, end: 1.5),
            TimedText(text: "Hi! ", start: 2.2, end: 2.6),
            TimedText(text: "Bye.", start: 4.5, end: 5),
        ]
        #expect(Speakers.turns(pieces, spans: spans) == [
            Turn(speaker: 1, text: "Hello there."),
            Turn(speaker: 2, text: "Hi!"),
            Turn(speaker: 1, text: "Bye."),
        ])
    }

    @Test func pieceAcrossABoundaryGoesToTheLargerOverlap() {
        let pieces = [TimedText(text: "word", start: 1.5, end: 3)]
        #expect(Speakers.turns(pieces, spans: spans) == [Turn(speaker: 1, text: "word")])
    }

    @Test func pieceInAGapGoesToTheNearestSpan() {
        let gapped = [SpeakerSpan(speaker: "A", start: 0, end: 1), SpeakerSpan(speaker: "B", start: 5, end: 6)]
        let pieces = [TimedText(text: "a ", start: 0, end: 1), TimedText(text: "b", start: 4, end: 4.5)]
        #expect(Speakers.turns(pieces, spans: gapped) == [Turn(speaker: 1, text: "a"), Turn(speaker: 2, text: "b")])
    }

    @Test func blankPiecesStayWithThePreviousSpeaker() {
        let pieces = [
            TimedText(text: "One", start: 0, end: 1),
            TimedText(text: " ", start: 2.5, end: 2.6),
            TimedText(text: "two", start: 1, end: 1.5),
        ]
        #expect(Speakers.turns(pieces, spans: spans) == [Turn(speaker: 1, text: "One two")])
    }

    @Test func noSpansGivesOneTurn() {
        let pieces = [TimedText(text: "just me", start: 0, end: 1)]
        #expect(Speakers.turns(pieces, spans: []) == [Turn(speaker: 1, text: "just me")])
    }

    @Test func format() {
        #expect(Speakers.format([Turn(speaker: 1, text: "a"), Turn(speaker: 2, text: "b")]) == "Speaker 1: a\n\nSpeaker 2: b")
    }

    @Test func speakerOptions() throws {
        #expect(try Options.parse(["--speakers", "x.m4a"]) == Options(file: "x.m4a", speakers: true))
        #expect(try Options.parse(["--num-speakers=3", "x.m4a"]) == Options(file: "x.m4a", speakers: true, speakerCount: 3))
        #expect(throws: OptionsError.self) { try Options.parse(["--num-speakers", "0", "x.m4a"]) }
        #expect(throws: OptionsError.self) { try Options.parse(["--live", "--speakers"]) }
    }
}
