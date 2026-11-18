// pdf-ocr: OCR a PDF on-device with Apple's Vision framework.
//
// Each page is rendered with PDFKit, then read with VNRecognizeTextRequest. Then TextFix
// replaces known misreadings from the names file and corrects OCR mistakes with the
// on-device language model. Nothing leaves the machine.

import Foundation
import NaturalLanguage
import PDFKit
import TextFix
import Vision

struct Options {
    var input: String?
    var languages = ["es-ES", "en-US"]
    var scale: CGFloat = 3.0
    var fast = false
    var noCorrection = false
    var embeddedFirst = false
    var raw = false
    var namesPath: String?
    var instruct: String?
}

let usage = """
Usage: pdf-ocr [options] <file.pdf>

Options:
  -l, --languages <list>  Comma-separated recognition languages (default: es-ES,en-US)
  -s, --scale <n>         Render scale relative to 72 dpi (default: 3.0, about 216 dpi)
      --fast              Use the fast recognizer instead of the accurate one
      --no-correction     Turn off language correction
      --embedded-first    Use the page's embedded text when it has some; OCR only scanned pages
      --list-languages    Print the languages Vision supports and exit
      --raw               Skip names replacement and the language-model correction
      --names <path>      Names file to use instead of pdf-ocr/names.txt
      --instruct <text>   Custom correction instruction for this run
  -h, --help              Show this help

Text goes to stdout. Each page starts with a line "===== Page N =====".
OCR'd pages are corrected; embedded text (--embedded-first) is printed as it is.
"""

/// The progress line ("correcting page 3/10") is drawn only when stderr is a terminal.
let stderrIsTerminal = isatty(STDERR_FILENO) == 1 && ProcessInfo.processInfo.environment["TERM"] != "dumb"
/// Only the main flow writes to stderr, one call at a time.
nonisolated(unsafe) var progressShown = false

/// Writes a line to stderr, clearing the progress line first.
func printError(_ message: String) {
    clearProgress()
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

func showProgress(_ text: String) {
    guard stderrIsTerminal else { return }
    FileHandle.standardError.write(Data("\r\u{1B}[2K\(text)".utf8))
    progressShown = true
}

func clearProgress() {
    guard progressShown else { return }
    FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
    progressShown = false
}

func fail(_ message: String) -> Never {
    printError("pdf-ocr: \(message)")
    exit(1)
}

/// The page's language among the recognition languages, if the correction has instructions for it.
/// nil (unknown, or a language without instructions) tells the model to keep the text's own language.
func pageLanguage(_ text: String, candidates: [String]) -> Language? {
    if candidates.count == 1 { return Language(code: candidates[0]) }
    let recognizer = NLLanguageRecognizer()
    let constraints = candidates.compactMap { $0.split(whereSeparator: { $0 == "-" || $0 == "_" }).first }
        .map { NLLanguage(rawValue: $0.lowercased()) }
    if !constraints.isEmpty { recognizer.languageConstraints = constraints }
    recognizer.processString(text)
    return recognizer.dominantLanguage.flatMap { Language(code: $0.rawValue) }
}

func makeRequest(_ opts: Options) -> VNRecognizeTextRequest {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = opts.fast ? .fast : .accurate
    req.recognitionLanguages = opts.languages
    req.usesLanguageCorrection = !opts.noCorrection
    return req
}

func parseArgs() -> Options {
    var opts = Options()
    var args = CommandLine.arguments.dropFirst()
    while let arg = args.popFirst() {
        switch arg {
        case "-h", "--help":
            print(usage); exit(0)
        case "-l", "--languages":
            guard let v = args.popFirst() else { fail("\(arg) needs a value") }
            opts.languages = v.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        case "-s", "--scale":
            guard let v = args.popFirst(), let d = Double(v), d > 0 else { fail("\(arg) needs a positive number") }
            opts.scale = CGFloat(d)
        case "--fast":
            opts.fast = true
        case "--no-correction":
            opts.noCorrection = true
        case "--embedded-first":
            opts.embeddedFirst = true
        case "--raw":
            opts.raw = true
        case "--names":
            guard let v = args.popFirst() else { fail("\(arg) needs a value") }
            opts.namesPath = v
        case "--instruct":
            guard let v = args.popFirst() else { fail("\(arg) needs a value") }
            opts.instruct = v
        case "--list-languages":
            let langs = (try? makeRequest(opts).supportedRecognitionLanguages()) ?? []
            print(langs.joined(separator: "\n")); exit(0)
        default:
            if arg.hasPrefix("-") { fail("unknown option \(arg)\n\n\(usage)") }
            if opts.input != nil { fail("only one input file is supported") }
            opts.input = arg
        }
    }
    return opts
}

func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
    let bounds = page.bounds(for: .mediaBox)
    let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
    guard w > 0, h > 0,
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: ctx)
    return ctx.makeImage()
}

let opts = parseArgs()
guard let path = opts.input else { fail("no input file\n\n\(usage)") }
guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else { fail("cannot open PDF: \(path)") }

let names = opts.raw ? [] : Names.load(explicit: opts.namesPath, tool: "pdf-ocr", warn: printError)
let useModel: Bool = {
    if opts.raw { return false }
    if let reason = Cleanup.unavailableReason {
        printError("warning: language model unavailable (\(reason)); OCR text not corrected")
        return false
    }
    return true
}()

/// Names replacement, then the language-model correction (unless --raw).
func correct(_ text: String, page: Int) async -> String {
    if opts.raw { return text }
    let named = Names.apply(names, to: text)
    guard useModel, !named.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return named }
    let language = pageLanguage(named, candidates: opts.languages)
    return await Cleanup.run(
        named, source: .ocr, language: language, names: names, instruction: opts.instruct,
        warn: { printError("page \(page): \($0)") }
    ) { number, total in
        showProgress("Correcting page \(page)/\(doc.pageCount)" + (total > 1 ? ", part \(number)/\(total)" : ""))
    }
}

for i in 0..<doc.pageCount {
    print("===== Page \(i + 1) =====")
    guard let page = doc.page(at: i) else { continue }

    if opts.embeddedFirst, let text = page.string,
       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        print(text)
        continue
    }

    guard let image = render(page, scale: opts.scale) else {
        printError("pdf-ocr: could not render page \(i + 1)")
        continue
    }
    showProgress("Reading page \(i + 1)/\(doc.pageCount)")
    let req = makeRequest(opts)
    do {
        try VNImageRequestHandler(cgImage: image).perform([req])
    } catch {
        fail("Vision failed on page \(i + 1): \(error). If you run this inside a sandbox, Vision may not be able to load its models.")
    }
    // Vision returns observations roughly top-to-bottom already.
    let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    let text = await correct(lines.joined(separator: "\n"), page: i + 1)
    clearProgress()
    print(text)
}
clearProgress()
