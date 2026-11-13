import Testing
@testable import DictateCore

@Suite struct TimestampsTests {
    // One piece per word, as SpeechTranscriber gives them with audio time ranges.
    let heard = [
        TimedText(text: "um ", start: 0, end: 0.5),
        TimedText(text: "so ", start: 0.5, end: 1),
        TimedText(text: "the ", start: 1, end: 1.2),
        TimedText(text: "the ", start: 1.2, end: 1.4),
        TimedText(text: "budget ", start: 1.4, end: 2),
        TimedText(text: "is ", start: 2, end: 2.2),
        TimedText(text: "ready ", start: 2.2, end: 3),
        TimedText(text: "uh ", start: 4, end: 4.5),
        TimedText(text: "can ", start: 65, end: 65.3),
        TimedText(text: "you ", start: 65.3, end: 65.5),
        TimedText(text: "check ", start: 65.5, end: 66),
        TimedText(text: "it", start: 66, end: 66.5),
    ]

    @Test func cleanedSentencesGetTheTimeOfTheirFirstHeardWord() {
        let (sentences, matched) = Timestamps.align("So the budget is ready. Can you check it?", to: heard)
        #expect(sentences == [
            TimedSentence(start: 0.5, text: "So the budget is ready."),
            TimedSentence(start: 65, text: "Can you check it?"),
        ])
        #expect(matched == 1)
    }

    @Test func rawTextAlignsToItself() {
        let (sentences, matched) = Timestamps.align(Timestamps.rawText(heard), to: heard)
        #expect(sentences.map(\.start) == [0])
        #expect(matched == 1)
    }

    @Test func accentsAndCapitalsStillMatch() {
        let pieces = [TimedText(text: "que ", start: 1, end: 2), TimedText(text: "tal", start: 2, end: 3)]
        #expect(Timestamps.align("¿Qué tal?", to: pieces).sentences == [TimedSentence(start: 1, text: "¿Qué tal?")])
    }

    @Test func sentenceWithNoHeardWordStartsAfterThePreviousOne() {
        let (sentences, matched) = Timestamps.align("So the budget is ready. Totally new words here. Can you check it?", to: heard)
        #expect(sentences.map(\.start) == [0.5, 4, 65])
        #expect(matched < 1)
    }

    @Test func timesNeverGoBackwards() {
        let (sentences, _) = Timestamps.align("Can you check it? The budget is ready.", to: heard)
        #expect(sentences.count == 2)
        #expect(sentences[0].start <= sentences[1].start)
    }

    @Test func freeRewriteIsReportedAsRough() {
        let (_, matched) = Timestamps.align("Dear team, please review the attached figures.", to: heard)
        #expect(matched < Timestamps.roughBelow)
    }

    @Test func stamp() {
        #expect(Timestamps.stamp(0) == "[00:00:00]")
        #expect(Timestamps.stamp(83.9) == "[00:01:23]")
        #expect(Timestamps.stamp(3725) == "[01:02:05]")
    }

    @Test func formats() {
        let a = [TimedSentence(start: 0, text: "Hi."), TimedSentence(start: 3, text: "Ready?")]
        let b = [TimedSentence(start: 5, text: "Yes.")]
        #expect(Timestamps.format(a) == "[00:00:00] Hi.\n[00:00:03] Ready?")
        #expect(Timestamps.format([(speaker: 1, sentences: a), (speaker: 2, sentences: b)])
            == "[00:00:00] Speaker 1: Hi.\n[00:00:03] Ready?\n\n[00:00:05] Speaker 2: Yes.")
    }

    @Test func speakerGroupsKeepTheirPieces() {
        let spans = [SpeakerSpan(speaker: "A", start: 0, end: 10), SpeakerSpan(speaker: "B", start: 60, end: 70)]
        let groups = Speakers.groups(heard, spans: spans)
        #expect(groups.map(\.speaker) == [1, 2])
        #expect(groups.map(\.pieces.count) == [8, 4])
    }

    @Test func options() throws {
        #expect(try Options.parse(["--timestamps", "x.m4a"]) == Options(file: "x.m4a", timestamps: true))
        #expect(throws: OptionsError.self) { try Options.parse(["--live", "--timestamps"]) }
        #expect(throws: OptionsError.self) { try Options.parse(["--timestamps=yes", "x.m4a"]) }
    }
}
