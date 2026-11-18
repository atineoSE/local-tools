# local-tools

Small command-line tools that run fully on this Mac, using Apple's on-device frameworks. Your data never leaves the machine. The only network use is a one-time model download (see each tool).

## Tools

### pdf-ocr

Reads the text in a PDF with Apple's Vision framework, then corrects OCR mistakes with
[textfix](#textfix). Use it for scanned PDFs, which have no text layer.

```sh
cd pdf-ocr
make                 # builds .build/release/pdf-ocr (bin/pdf-ocr links to it)
make install         # optional: symlinks it into ~/.local/bin (change with PREFIX=...)

pdf-ocr document.pdf > document.txt
pdf-ocr -l en-US --fast notes.pdf
pdf-ocr --embedded-first mixed.pdf    # OCR only the pages that have no text layer
pdf-ocr --raw document.pdf            # Vision's text exactly, no names fix, no correction
pdf-ocr --list-languages
```

How it works: PDFKit renders each page as an image (3× scale by default, about 216 dpi). Vision's `VNRecognizeTextRequest` then reads it in accurate mode, with language correction on. The default languages are Spanish and English.

Then, for each OCR'd page, `pdf-ocr` replaces known misreadings from its names file and asks the on-device language model to fix OCR mistakes: misread letters and digits ("rn" for "m", "1" for "l", "0" for "O"), missing accents, split or run-together words, and stray symbols. Each line stays on its own line. The model is told the page's language (detected among the `-l` languages; Spanish and English get specific instructions) and must not translate, rephrase, or add anything. A line the model added (made mostly of words that are not on the page) is removed, with a warning on stderr. If the model is unavailable, you get Vision's text and one warning. Pages read from the embedded text layer (`--embedded-first`) are printed exactly as they are.

The correction is good at small errors. On a badly blurred scan, where Vision's text is mostly garbled, the model can guess wrong words. Use `--raw` to compare.

| Flag | Default | Description |
|------|---------|-------------|
| `-l`, `--languages` | `es-ES,en-US` | Recognition languages, comma-separated |
| `-s`, `--scale` | `3.0` | Render scale relative to 72 dpi |
| `--fast` | off | Fast recognizer instead of the accurate one |
| `--no-correction` | off | Turn off Vision's own language correction (not the model correction; that is `--raw`) |
| `--embedded-first` | off | Use a page's embedded text when it has some; OCR only scanned pages |
| `--raw` | off | Skip names replacement and the model correction |
| `--names` | `pdf-ocr/names.txt` | Names file to use instead of the default |
| `--instruct` | none | Custom correction instruction for this run |
| `--list-languages` | — | Print the languages Vision supports and exit |

Names file: same format as [dictate's](#names-file). Write the misreadings after `seen:` (`heard:` also works). The default file `pdf-ocr/names.txt` is git-ignored; start from the example:

```sh
cp pdf-ocr/names.example.txt pdf-ocr/names.txt
```

OCR misreadings differ from speech mishearings ("Mistra1", not "miss trail"), so each tool has its own file. The default file is found through the symlink back to the repo, so `make install` makes a symlink, not a copy.

Requirements: macOS 26+ with the Xcode command-line tools (Swift 6). The model correction needs Apple Intelligence (see [dictate's requirements](#requirements)); without it, `pdf-ocr` still prints Vision's text.

Sandboxes: inside a restrictive sandbox, such as the Claude Code bash sandbox, two things can fail:
- `swift build` cannot compile the package manifest. Build outside the sandbox.
- Vision cannot load its models and fails with `nilError`. Run the binary outside the sandbox.

### textfix

The correction step that `dictate` and `pdf-ocr` share, as a Swift library (`TextFix`) and a command. It does two things, both on-device:

1. **Names replacement.** Known misrecognitions from a names file are replaced with the right name, deterministically.
2. **Language-model clean-up** with Apple's on-device model (FoundationModels). The *source* chooses the instructions:
   - `dictation`: remove fillers, repeated words and false starts; fix punctuation. Lines are joined into sentences.
   - `ocr`: fix misread characters, split words and stray symbols. Line breaks are kept.

   Both keep the wording, never summarise, never translate, and protect the spellings of the names the text uses. Long text goes to the model in chunks of up to 1,500 characters. A sentence the model added is removed, with a warning. For `ocr`, a word within one or two letter edits of a word in the input still counts as present, because it is probably a correction.

```bash
swift build -c release --package-path textfix
textfix/.build/release/textfix --source ocr --language es --names pdf-ocr/names.txt page.txt
pbpaste | textfix/.build/release/textfix --source dictation --language en
```

| Flag | Default | Description |
|------|---------|-------------|
| `FILE` | stdin | Text to correct |
| `--source` | `dictation` | `dictation` or `ocr` |
| `--language` | none | `en` or `es` (also `es-ES` etc.); without it, the model keeps the text's language |
| `--names` | none | Names file |
| `--instruct` | none | Custom instruction instead of the light default |
| `--no-model` | off | Names replacement only |

Layout:

```
textfix/             Swift package, used by dictate and pdf-ocr through a path dependency
  Sources/TextFix/
    Names.swift        names file parsing, default path per tool, misrecognition replacement
    Cleanup.swift      clean-up via FoundationModels: per-source instructions, chunking, added-text check
    Language.swift     en/es and their names in the instructions
  Sources/TextFixCLI/main.swift    the textfix command
  Tests/TextFixTests/
```

### dictate

`dictate` does speech-to-text on-device with Apple's Speech framework, then
cleans the text up with Apple's on-device language model (FoundationModels),
through [textfix](#textfix).
Nothing goes to the cloud and there is no API key. Speaker labels
(`--speakers`) use [FluidAudio](https://github.com/FluidInference/FluidAudio),
also on-device. It is a Swift package in `dictate/`.

#### Requirements

- macOS 26+ on Apple Silicon, with Apple Intelligence turned on
- Xcode command-line tools (Swift 6) — `xcode-select --install`
- No API key

> **Setup gotcha: Siri language.** The language model stays unavailable —
> `fm available` reports `modelNotReady`, and there is no Apple Intelligence
> toggle in System Settings — until the **Siri language matches the system
> language** (e.g. both English (United States)). Siri itself can stay off.
> After changing it, the model downloads in about 20 minutes. The speech model
> for each language downloads separately, the first time you use it.

#### Build and install

From the repo root:

```bash
swift build -c release --package-path dictate
mkdir -p ~/.local/bin
ln -sf "$PWD/dictate/.build/release/dictate" ~/.local/bin/dictate
```

With the symlink, rebuilding updates the command in place. The symlink is also how `dictate` finds its default names file — it
resolves the link back to the repo.

#### File mode

Point it at an audio file; the cleaned transcript goes to stdout, progress and
errors to stderr:

```bash
dictate memo.m4a
dictate memo.m4a --raw                     # exactly what was heard, no names fix, no clean-up
dictate nota.m4a --language es             # Spanish
dictate memo.m4a --instruct "Turn this into a bulleted list"
dictate memo.m4a > memo.txt
```

The default clean-up is deliberately light: it removes filler words ("um",
"you know"; "eh", "o sea"), repeated words and false starts, and fixes obvious
punctuation. It keeps your wording and sentence order, never summarises, and
never translates — Spanish in, Spanish out. `--instruct` replaces that light
instruction for one run. If the language model is unavailable or refuses, a
warning goes to stderr and you get the uncleaned text rather than nothing.
The light clean-up also checks each chunk it gets back: if the model added a
sentence made mostly of words you did not say (it sometimes introduces itself
— "Soy una inteligencia artificial desarrollada por Apple."), that sentence
is removed and named in a warning on stderr. `--instruct` runs skip this check,
because a rewrite may add words on purpose.

#### Speaker labels

`--speakers` labels who spoke, in file mode only:

```bash
dictate meeting.m4a --speakers
dictate meeting.m4a --num-speakers 2       # exact speaker count; implies --speakers
```

```
Speaker 1: Hi, Daniel. Thanks for joining. Did you get a chance to look at the budget?

Speaker 2: Yes, I went through it last night.
```

Speakers are numbered in the order they first speak. Names replacement and
clean-up run on each turn separately, so the labels are never changed. Use
`--num-speakers` when you know the count; without it, the number of speakers
is estimated and can come out too high or too low.

The first `--speakers` run downloads about 22 MB of speaker models from
Hugging Face to `~/Library/Application Support/FluidAudio/Models/`. After that,
it works offline.

#### Progress

When stderr is a terminal, one status line there shows what is running, how
far it has got, and the time since the run started:

```
⠦ Transcribing 42% · Finding speakers 83% · 0:12
```

Transcription counts how much of the audio is done. Speaker detection counts
its segmentation steps and waits at 99% while it groups the voices. Clean-up
counts turns (with `--speakers`) and the parts of a long text. Model downloads
show a percentage (speech) or the spinner only (speaker models). The line goes
away before the transcript prints. When stderr goes to a file, a pipe, or
the keyboard shortcut, nothing is shown.

#### Timestamps

`--timestamps` puts the start time before each sentence, in file mode only:

```bash
dictate meeting.m4a --timestamps
dictate meeting.m4a --timestamps --speakers
```

```
[00:00:00] Speaker 1: Hi, Daniel. Thanks for joining.
[00:00:03] Did you get a chance to look at the budget?

[00:00:07] Speaker 2: Yes, I went through it last night.
```

Clean-up still sees the whole text (or the whole turn, with `--speakers`).
Afterwards, the words of each cleaned sentence are matched back to the words
as heard, and the sentence takes the time of its first matched word. The light
clean-up only removes words and fixes punctuation, so almost every word
matches. An `--instruct` rewrite can change the wording a lot; when fewer
than half of the words match, a warning on stderr says the times are
approximate. Times are rounded down to the second.

#### Live mode

```bash
dictate --live
dictate --live --language es
dictate --live --raw
```

`--live` records from the microphone until you stop it, then cleans up the
text, copies it to the clipboard, and prints it to stdout.

- **Sounds:** Tink when recording starts (once audio is actually flowing),
  Pop when it stops, Glass when the text is ready on the clipboard.
- **Stop:** run `dictate --live` a second time — that stops the first one and
  exits. In a terminal, pressing Enter also stops it.
- **Cancel:** Ctrl-C stops without copying anything (exit code 130).
- **Errors** (no microphone permission, model download failure, nothing
  heard) are shown as a macOS notification as well as on stderr, since there
  may be no terminal open.

#### Names file

Speech recognition mangles unusual names ("Voxtral" comes out as "rock
stroll", "Mistral" as "Miss Trail"), and neither its hint list nor the
language model can be trusted to fix them. So `dictate` replaces known
mishearings with the right name, deterministically, before clean-up. You
teach it new mishearings as you find them.

The default file is `dictate/names.txt`. It is git-ignored, since it
holds your own names; start from the committed example:

```bash
cp dictate/names.example.txt dictate/names.txt
```

One entry per line, UTF-8:

```
# comment lines and blank lines are ignored
Voxtral, Mistral's speech model, heard: rock stroll | box trawl | foxtraw
Mistral, AI company from Paris, heard: miss trail | mostral
Arthur
```

- The **name** is everything before the first comma.
- The optional **context** follows it (it may contain commas). When the name
  appears in the transcript, it is passed to the language model, along with
  the context, as a spelling to keep unchanged.
- The optional **`heard:`** field lists what the recogniser writes instead,
  separated by `|`. Each variant is replaced with the name, case-insensitively
  and on whole words only; longer variants win over shorter ones.

Whenever a name comes out wrong, add what you got as another `heard:`
variant. `--names PATH` uses a different file for one run (if it does not
exist, a warning goes to stderr and no names are replaced); `--raw` skips the
replacement entirely.

#### Keyboard shortcut

To dictate from anywhere with one key combination:

1. Open the **Shortcuts** app and create a new shortcut.
2. Add a **Run Shell Script** action containing `~/.local/bin/dictate --live`.
3. Open the shortcut's details and choose **Add Keyboard Shortcut**.

Press it to start recording and press it again to stop; the text lands on the
clipboard. The first run asks for microphone permission for Shortcuts.

#### Limits

- One language per run. Mixed-language speech comes out as nonsense.
- Speaker labels in file mode only, not with `--live`.
- Timestamps in file mode only, not with `--live`.

#### Options

| Flag | Default | Description |
|------|---------|-------------|
| `FILE` | — | Audio file to transcribe (file mode; omit with `--live`) |
| `--live` | off | Record from the microphone until stopped; copy the result to the clipboard |
| `--language` | `en` | Spoken language: `en` or `es` |
| `--raw` | off | Skip names replacement and clean-up |
| `--instruct` | none | Custom clean-up instruction for this run |
| `--names` | `dictate/names.txt` | Names file to use instead of the default |
| `--speakers` | off | Label who spoke (`Speaker 1: …`); file mode only |
| `--num-speakers` | none | Exact number of speakers (implies `--speakers`) |
| `--timestamps` | off | Start time before each sentence (`[00:01:23] …`); file mode only |
| `--simulate-mic` | none | Testing only: live mode reads this audio file at real-time speed instead of the microphone (implies `--live`) |
| `-h`, `--help` | — | Show usage and exit |

#### Layout

```
dictate/             Swift package, Apple on-device speech + language model
  Package.swift
  Sources/dictate/main.swift        entrypoint
  Sources/DictateCore/
    Options.swift      flag parsing
    Transcribe.swift   file-mode transcription via SpeechTranscriber
    Speakers.swift     diarization via FluidAudio, text-to-speaker alignment
    Timestamps.swift   sentence start times: cleaned words matched back to heard words
    Live.swift         microphone recording, start/stop toggle via lock file
    Pipeline.swift     names → clean-up, both from textfix (../textfix)
    Stderr.swift       stderr messages, progress status line, library-output filter
    Feedback.swift     sounds, clipboard, error notifications
  Tests/DictateCoreTests/
  fixtures/            English and Spanish test recordings
  names.example.txt    template for the git-ignored names.txt
```

#### Credits

`dictate --speakers` uses third-party code and models:

- [FluidAudio](https://github.com/FluidInference/FluidAudio) by Fluid
  Inference — Apache-2.0. It includes fastcluster (BSD-2-Clause) and VBx
  (Apache-2.0); their license texts are in FluidAudio's
  [`ThirdPartyLicenses/`](https://github.com/FluidInference/FluidAudio/tree/main/ThirdPartyLicenses).
- Speaker diarization models from
  [FluidInference/speaker-diarization-coreml](https://huggingface.co/FluidInference/speaker-diarization-coreml),
  licensed [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/). They are
  Core ML conversions (modified from the originals) of:
  - [pyannote speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1)
    by pyannote — CC-BY-4.0
  - [WeSpeaker ResNet34 speaker embeddings](https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM)
    by WeSpeaker — CC-BY-4.0
  - PLDA parameters by [BUT Speech@FIT](https://speech.fit.vut.cz/) — CC-BY-4.0

The models are not part of this repo; FluidAudio downloads them on first use.
See the model repo's
[NOTICE.md](https://huggingface.co/FluidInference/speaker-diarization-coreml/blob/main/NOTICE.md)
for the full attribution.
