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
