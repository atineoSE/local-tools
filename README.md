# local-tools

Small command-line tools that run fully on this Mac, using Apple's on-device frameworks. They make no network calls.

## Tools

### pdf-ocr

Reads the text in a PDF with Apple's Vision framework. Use it for scanned PDFs, which have no text layer.

```sh
cd pdf-ocr
make                 # builds bin/pdf-ocr
make install         # optional: copies it to ~/.local/bin (change with PREFIX=...)

pdf-ocr document.pdf > document.txt
pdf-ocr -l en-US --fast notes.pdf
pdf-ocr --embedded-first mixed.pdf    # OCR only the pages that have no text layer
pdf-ocr --list-languages
```

How it works: PDFKit renders each page as an image (3× scale by default, about 216 dpi). Vision's `VNRecognizeTextRequest` then reads it in accurate mode, with language correction on. The default languages are Spanish and English.

Requirements: macOS with the Xcode command-line tools (`swiftc`).

Sandboxes: inside a restrictive sandbox, such as the Claude Code bash sandbox, two things can fail:
- The build cannot write to the default Clang module cache. The Makefile avoids this because it uses `.build/module-cache`.
- Vision cannot load its models and fails with `nilError`. Run the binary outside the sandbox.
