// textfix: correct recognised text (dictation or OCR) with a names file and the on-device language model.
import Foundation
import TextFix

let usage = """
    usage: textfix [--source dictation|ocr] [--language en|es] [--names PATH] [--instruct TEXT] [--no-model] [FILE]

    Corrects text from speech recognition or OCR, on-device. Reads FILE (or stdin), writes stdout.

      --source dictation|ocr  what produced the text (default: dictation)
      --language en|es        language of the text (default: none, the model keeps the text's language)
      --names PATH            names file: replace known misrecognitions, protect name spellings
      --instruct TEXT         custom clean-up instruction instead of the light default
      --no-model              names replacement only; skip the language model
      -h, --help              show this help
    """

func fail(_ message: String, code: Int32 = 2) -> Never {
    standardErrorWarning("textfix: \(message)")
    exit(code)
}

var source = Source.dictation
var language: Language?
var namesPath: String?
var instruction: String?
var useModel = true
var file: String?

var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    func value() -> String {
        guard let v = args.popFirst() else { fail("\(arg) requires a value\n\n\(usage)") }
        return v
    }
    switch arg {
    case "-h", "--help":
        print(usage); exit(0)
    case "--source":
        let v = value()
        guard let s = Source(rawValue: v) else { fail("unknown source '\(v)' (expected dictation or ocr)") }
        source = s
    case "--language":
        let v = value()
        guard let l = Language(code: v) else { fail("unsupported language '\(v)' (expected en or es)") }
        language = l
    case "--names":
        namesPath = value()
    case "--instruct":
        instruction = value()
    case "--no-model":
        useModel = false
    default:
        if arg.hasPrefix("-"), arg != "-" { fail("unknown option '\(arg)'\n\n\(usage)") }
        if file != nil { fail("expected one FILE") }
        file = arg
    }
}

let input: String
if let file, file != "-" {
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { fail("cannot read \(file)", code: 1) }
    input = text
} else {
    input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
}

let names: [NameEntry]
if let namesPath {
    names = Names.load(explicit: namesPath, tool: "textfix", warn: standardErrorWarning)
} else {
    names = []
}
let named = Names.apply(names, to: input)
let output = useModel
    ? await Cleanup.run(named, source: source, language: language, names: names, instruction: instruction)
    : named
print(output.trimmingCharacters(in: .newlines))
