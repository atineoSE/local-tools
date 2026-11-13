import Foundation

public enum Language: String, Sendable, CaseIterable {
    case en, es

    /// Locale identifier handed to the Speech framework.
    public var localeID: String {
        switch self {
        case .en: "en-US"
        case .es: "es-ES"
        }
    }
}

public struct Options: Equatable, Sendable {
    public var file: String?
    public var live: Bool
    public var language: Language
    public var raw: Bool
    public var instruct: String?
    public var namesPath: String?
    public var simulateMic: String?
    /// Label who spoke (file mode only).
    public var speakers: Bool
    /// Exact number of speakers for diarization; nil lets it decide.
    public var speakerCount: Int?
    /// Start time before each sentence (file mode only).
    public var timestamps: Bool

    public init(
        file: String? = nil,
        live: Bool = false,
        language: Language = .en,
        raw: Bool = false,
        instruct: String? = nil,
        namesPath: String? = nil,
        simulateMic: String? = nil,
        speakers: Bool = false,
        speakerCount: Int? = nil,
        timestamps: Bool = false
    ) {
        self.file = file
        self.live = live
        self.language = language
        self.raw = raw
        self.instruct = instruct
        self.namesPath = namesPath
        self.simulateMic = simulateMic
        self.speakers = speakers
        self.speakerCount = speakerCount
        self.timestamps = timestamps
    }

    public static let usage = """
        usage: dictate [--language en|es] [--raw] [--instruct TEXT] [--names PATH] [--speakers [--num-speakers N]] [--timestamps] FILE
               dictate --live [--language en|es] [--raw] [--instruct TEXT] [--names PATH]
               dictate --simulate-mic FILE [flags]

        Local, on-device speech-to-text with optional clean-up.

          FILE                 audio file to transcribe (file mode)
          --live               record from the microphone until stopped (live mode)
          --language en|es     spoken language (default: en)
          --raw                skip names replacement and clean-up
          --instruct TEXT      custom clean-up instruction for this run
          --names PATH         names file to use instead of the default
          --speakers           label who spoke ("Speaker 1: …"); file mode only
          --num-speakers N     exact number of speakers (implies --speakers)
          --timestamps         start time before each sentence ("[00:01:23] …"); file mode only
          --simulate-mic FILE  testing only: live mode reads FILE instead of the microphone
          -h, --help           show this help
        """

    /// Parses command-line arguments (without the program name).
    public static func parse(_ arguments: [String]) throws(OptionsError) -> Options {
        var options = Options()
        var positionals: [String] = []
        var index = 0

        func value(for flag: String, inline: String?) throws(OptionsError) -> String {
            if let inline { return inline }
            index += 1
            guard index < arguments.count else { throw .invalid("\(flag) requires a value") }
            return arguments[index]
        }

        var onlyPositionals = false
        while index < arguments.count {
            let arg = arguments[index]
            if onlyPositionals || arg == "-" || !arg.hasPrefix("-") {
                positionals.append(arg)
                index += 1
                continue
            }
            var flag = arg
            var inline: String?
            if arg.hasPrefix("--"), let eq = arg.firstIndex(of: "=") {
                flag = String(arg[..<eq])
                inline = String(arg[arg.index(after: eq)...])
            }
            switch flag {
            case "--":
                onlyPositionals = true
            case "-h", "--help":
                throw .help
            case "--live":
                if inline != nil { throw .invalid("--live takes no value") }
                options.live = true
            case "--raw":
                if inline != nil { throw .invalid("--raw takes no value") }
                options.raw = true
            case "--language":
                let v = try value(for: flag, inline: inline)
                guard let language = Language(rawValue: v) else {
                    throw .invalid("unsupported language '\(v)' (expected en or es)")
                }
                options.language = language
            case "--instruct":
                options.instruct = try value(for: flag, inline: inline)
            case "--names":
                options.namesPath = try value(for: flag, inline: inline)
            case "--speakers":
                if inline != nil { throw .invalid("--speakers takes no value") }
                options.speakers = true
            case "--num-speakers":
                let v = try value(for: flag, inline: inline)
                guard let n = Int(v), n >= 1 else {
                    throw .invalid("--num-speakers expects a whole number of at least 1, got '\(v)'")
                }
                options.speakerCount = n
                options.speakers = true
            case "--timestamps":
                if inline != nil { throw .invalid("--timestamps takes no value") }
                options.timestamps = true
            case "--simulate-mic":
                options.simulateMic = try value(for: flag, inline: inline)
                options.live = true
            default:
                throw .invalid("unknown option '\(arg)'")
            }
            index += 1
        }

        if positionals.count > 1 {
            throw .invalid("expected one FILE, got \(positionals.count)")
        }
        options.file = positionals.first
        if options.live, options.file != nil {
            throw .invalid("FILE cannot be combined with --live or --simulate-mic")
        }
        if options.live, options.speakers {
            throw .invalid("--speakers works only with a FILE, not with --live")
        }
        if options.live, options.timestamps {
            throw .invalid("--timestamps works only with a FILE, not with --live")
        }
        if !options.live, options.file == nil {
            throw .invalid("missing FILE (or use --live)")
        }
        return options
    }
}

public enum OptionsError: Error, Equatable {
    /// `-h` / `--help` was given.
    case help
    /// Bad input; the message explains what was wrong.
    case invalid(String)
}
