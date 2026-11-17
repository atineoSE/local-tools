// pdf-ocr: OCR a PDF on-device with Apple's Vision framework.
//
// Each page is rendered with PDFKit, then read with VNRecognizeTextRequest.
// Nothing leaves the machine.

import Foundation
import PDFKit
import Vision

struct Options {
    var input: String?
    var languages = ["es-ES", "en-US"]
    var scale: CGFloat = 3.0
    var fast = false
    var noCorrection = false
    var embeddedFirst = false
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
  -h, --help              Show this help

Text goes to stdout. Each page starts with a line "===== Page N =====".
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("pdf-ocr: \(message)\n".utf8))
    exit(1)
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

for i in 0..<doc.pageCount {
    print("===== Page \(i + 1) =====")
    guard let page = doc.page(at: i) else { continue }

    if opts.embeddedFirst, let text = page.string,
       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        print(text)
        continue
    }

    guard let image = render(page, scale: opts.scale) else {
        FileHandle.standardError.write(Data("pdf-ocr: could not render page \(i + 1)\n".utf8))
        continue
    }
    let req = makeRequest(opts)
    do {
        try VNImageRequestHandler(cgImage: image).perform([req])
    } catch {
        fail("Vision failed on page \(i + 1): \(error). If you run this inside a sandbox, Vision may not be able to load its models.")
    }
    // Vision returns observations roughly top-to-bottom already.
    let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    print(lines.joined(separator: "\n"))
}
