import AppKit
import Foundation
import Testing
@testable import DictateCore

@Suite(.serialized) struct FeedbackTests {
    @Test func copyToClipboardRoundTrip() {
        let pasteboard = NSPasteboard.general
        // Save every item and type on the clipboard so it can be restored exactly.
        let saved: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        defer {
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
        }

        let unique = "dictate-test-\(UUID().uuidString)"
        Feedback.copyToClipboard(unique)
        #expect(pasteboard.string(forType: .string) == unique)
    }

    @Test(arguments: [Cue.start, .stop, .ready])
    func playReturnsPromptly(cue: Cue) {
        let start = Date()
        Feedback.play(cue)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func notificationScriptEscapes() {
        #expect(Feedback.notificationScript(#"say "hi" \ bye"#)
            == #"display notification "say \"hi\" \\ bye" with title "dictate""#)
    }
}

@Suite struct StatusTests {
    @Test func line() {
        let stages = [(name: "Transcribing", detail: "42%"), (name: "Finding speakers", detail: "")]
        #expect(Status.line(frame: 0, stages: stages, elapsed: 72.5) == "⠋ Transcribing 42% · Finding speakers · 1:12")
        #expect(Status.line(frame: 11, stages: [], elapsed: 0) == "⠙ 0:00")
    }

    @Test func percentIsClampedAndRoundedDown() {
        #expect(Status.percent(0.429) == "42%")
        #expect(Status.percent(1.3) == "100%")
        #expect(Status.percent(-1) == "0%")
    }

    @Test func cleanupDetail() {
        #expect(DictateCore.cleanupDetail(turn: nil, chunk: (1, 1)) == "")
        #expect(DictateCore.cleanupDetail(turn: nil, chunk: (2, 3)) == "part 2/3")
        #expect(DictateCore.cleanupDetail(turn: (2, 5), chunk: (1, 1)) == "turn 2/5")
        #expect(DictateCore.cleanupDetail(turn: (1, 1), chunk: (1, 1)) == "")
        #expect(DictateCore.cleanupDetail(turn: (2, 5), chunk: (3, 4)) == "turn 2/5, part 3/4")
    }

    @Test func disabledStatusWritesNothingButMessages() {
        let status = Status(enabled: false)
        status.set("Transcribing", fraction: 0.5)
        status.done("Transcribing")
        status.finish()
    }
}

@Suite struct StderrTests {
    @Test func droppingReturnsTheResultAndRestoresStderr() async throws {
        func identity() -> (dev_t, ino_t) {
            var info = stat()
            fstat(STDERR_FILENO, &info)
            return (info.st_dev, info.st_ino)
        }
        let before = identity()
        let value = try await Stderr.dropping(prefix: "[Profiling]") {
            FileHandle.standardError.write(Data("[Profiling] hidden\n".utf8))
            return 42
        }
        #expect(value == 42)
        #expect(identity() == before)
    }
}
