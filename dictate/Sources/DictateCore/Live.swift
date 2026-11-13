import AVFoundation
import Darwin
import Foundation
import Speech

public enum Live {
    /// Runs live mode and returns the process exit code.
    ///
    /// A second `dictate --live` while one is recording stops it (lock file + SIGUSR1).
    /// Enter (TTY only), SIGUSR1, or the end of a `--simulate-mic` file stop normally; Ctrl-C cancels (130).
    public static func run(options: Options) async -> Int32 {
        let (events, emit) = AsyncStream.makeStream(of: Event.self)
        let state = RunState()

        // Handlers go in before the PID is published, so an early stop press cannot kill us.
        let signals = [
            signalSource(SIGUSR1) { emit.yield(.stop(.normal)) },
            signalSource(SIGINT) {
                emit.yield(.stop(.cancel))
                // Still setting up (e.g. downloading the model): nothing to finish, leave now.
                if !state.recording {
                    state.lock?.release()
                    exit(130)
                }
            },
        ]
        defer { signals.forEach { $0.cancel() } }

        let lock = LiveLock(path: LiveLock.defaultPath)
        do {
            switch try lock.acquire() {
            case .running(let pid):
                kill(pid, SIGUSR1)
                printError("dictate: stopping the running recording (pid \(pid))")
                return 0
            case .acquired:
                break
            }
        } catch {
            return fail("cannot create lock file \(lock.path.path): \(error)")
        }
        state.lock = lock
        defer { lock.release() }

        do {
            return try await record(options: options, events: events, emit: emit, state: state)
        } catch {
            return fail("\(error)")
        }
    }

    enum StopReason: Sendable { case normal, cancel }

    enum Event: Sendable {
        case flowing
        case stop(StopReason)
        case failed(String)
    }

    private static func record(
        options: Options, events: AsyncStream<Event>, emit: AsyncStream<Event>.Continuation, state: RunState
    ) async throws -> Int32 {
        let source: AudioSource
        if let path = options.simulateMic {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw LiveError.message("no such file: \(url.path)")
            }
            source = try SimulatedMic(url: url)
        } else {
            source = try await Microphone()
        }

        let transcriber = try await Transcribe.makeTranscriber(language: options.language)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) ?? source.format
        let (input, feed) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let converter = try BufferConverter(from: source.format, to: format) { input in
            feed.yield(input)
        } onFirst: {
            emit.yield(.flowing)
        }

        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }

        try await analyzer.start(inputSequence: input)
        state.recording = true
        try source.start(
            onBuffer: { converter.convert($0) },
            onEnd: { emit.yield(.stop(.normal)) },
            onError: { emit.yield(.failed("\($0)")) }
        )
        if isatty(STDIN_FILENO) == 1 {
            printError("Recording… press Enter to stop, Ctrl-C to cancel.")
            Thread.detachNewThread {
                _ = readLine()
                emit.yield(.stop(.normal))
            }
        }

        var reason = StopReason.normal
        loop: for await event in events {
            switch event {
            case .flowing:
                Feedback.play(.start)
            case .stop(let r):
                reason = r
                break loop
            case .failed(let message):
                await source.stop()
                feed.finish()
                await analyzer.cancelAndFinishNow()
                collector.cancel()
                throw LiveError.message(message)
            }
        }

        await source.stop()
        feed.finish()
        Feedback.play(.stop)

        if reason == .cancel {
            await analyzer.cancelAndFinishNow()
            collector.cancel()
            printError("dictate: cancelled")
            return 130
        }

        Status.shared.set("Finishing transcription")
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let raw = try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        Status.shared.done("Finishing transcription")
        guard !raw.isEmpty else {
            printError("dictate: Nothing was heard")
            Feedback.notifyError("Nothing was heard")
            return 1
        }
        let text = await process(raw, options: options)
        Status.shared.finish()
        Feedback.copyToClipboard(text)
        print(text)
        fflush(stdout)
        Feedback.play(.ready)
        return 0
    }

    private static func fail(_ message: String) -> Int32 {
        Status.shared.finish()
        printError("dictate: \(message)")
        Feedback.notifyError(message)
        return 1
    }

    private static func signalSource(_ sig: Int32, _ handler: @escaping @Sendable () -> Void) -> DispatchSourceSignal {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        source.setEventHandler(handler: handler)
        source.resume()
        return source
    }
}

enum LiveError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let m): m
        }
    }
}

/// Shared between the signal handlers and the run.
private final class RunState: @unchecked Sendable {
    private let mutex = NSLock()
    private var _recording = false
    private var _lock: LiveLock?

    var recording: Bool {
        get { mutex.withLock { _recording } }
        set { mutex.withLock { _recording = newValue } }
    }

    var lock: LiveLock? {
        get { mutex.withLock { _lock } }
        set { mutex.withLock { _lock = newValue } }
    }
}

// MARK: - Lock file

/// `~/Library/Caches/dictate/live.pid`: the PID of the recording `dictate`, if any.
struct LiveLock: Sendable {
    enum Outcome: Equatable {
        /// This process now owns the lock.
        case acquired
        /// Another live `dictate` owns it.
        case running(pid_t)
    }

    static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/dictate/live.pid")
    }

    let path: URL
    let pid: pid_t
    let isDictate: @Sendable (pid_t) -> Bool

    init(path: URL, pid: pid_t = getpid(), isDictate: @escaping @Sendable (pid_t) -> Bool = LiveLock.isRunningDictate) {
        self.path = path
        self.pid = pid
        self.isDictate = isDictate
    }

    /// Takes the lock, replacing it if the PID it names is dead or not `dictate`.
    func acquire() throws -> Outcome {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        for _ in 0..<5 {
            let fd = open(path.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
            if fd >= 0 {
                let data = "\(pid)\n"
                let written = data.withCString { write(fd, $0, strlen($0)) }
                close(fd)
                guard written == data.utf8.count else {
                    unlink(path.path)
                    throw POSIXError(.EIO)
                }
                return .acquired
            }
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            if let owner = owner(), owner != pid, isDictate(owner) {
                return .running(owner)
            }
            unlink(path.path)  // stale
        }
        throw POSIXError(.EEXIST)
    }

    /// Removes the lock file if this process owns it.
    func release() {
        if owner() == pid { unlink(path.path) }
    }

    /// The PID written in the lock file, if it holds one.
    func owner() -> pid_t? {
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        guard let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return nil }
        return pid
    }

    /// True if `pid` is alive and its executable is named `dictate`.
    @Sendable static func isRunningDictate(_ pid: pid_t) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 || errno == EPERM else { return false }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        let name = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return name == "dictate"
    }
}

// MARK: - Audio

protocol AudioSource: Sendable {
    var format: AVAudioFormat { get }
    func start(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onEnd: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws
    func stop() async
}

/// Converts captured buffers to the analyzer's format and hands them on.
private final class BufferConverter: @unchecked Sendable {
    private let mutex = NSLock()
    private let converter: AVAudioConverter?
    private let target: AVAudioFormat
    private let output: (AnalyzerInput) -> Void
    private var onFirst: (() -> Void)?

    init(
        from source: AVAudioFormat, to target: AVAudioFormat,
        output: @escaping (AnalyzerInput) -> Void, onFirst: @escaping () -> Void
    ) throws {
        if source == target {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: source, to: target) else {
                throw LiveError.message("cannot convert audio from \(source) to \(target)")
            }
            self.converter = converter
        }
        self.target = target
        self.output = output
        self.onFirst = onFirst
    }

    func convert(_ buffer: AVAudioPCMBuffer) {
        mutex.withLock {
            guard buffer.frameLength > 0 else { return }
            var converted = buffer
            if let converter {
                let ratio = target.sampleRate / buffer.format.sampleRate
                let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
                guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
                var consumed = false
                var error: NSError?
                let status = converter.convert(to: out, error: &error) { _, inputStatus in
                    if consumed {
                        inputStatus.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    inputStatus.pointee = .haveData
                    return buffer
                }
                guard status != .error, out.frameLength > 0 else { return }
                converted = out
            }
            output(AnalyzerInput(buffer: converted))
            if let first = onFirst {
                onFirst = nil
                first()
            }
        }
    }
}

/// The real microphone, via an `AVAudioEngine` input tap.
private final class Microphone: AudioSource, @unchecked Sendable {
    private let engine = AVAudioEngine()
    let format: AVAudioFormat

    init() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw LiveError.message("microphone access was denied")
            }
        default:
            throw LiveError.message(
                "no microphone permission (System Settings → Privacy & Security → Microphone)")
        }
        format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw LiveError.message("no microphone available")
        }
    }

    func start(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onEnd: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            onBuffer(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw LiveError.message("cannot start the microphone: \(error)")
        }
    }

    func stop() async {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }
}

/// `--simulate-mic FILE`: the file's audio, delivered in small buffers at real-time pace.
private final class SimulatedMic: AudioSource, @unchecked Sendable {
    private let file: AVAudioFile
    private let mutex = NSLock()
    private var task: Task<Void, Never>?
    let format: AVAudioFormat

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        format = file.processingFormat
    }

    func start(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onEnd: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        let file = self.file
        let format = self.format
        let chunk = AVAudioFrameCount(max(1, format.sampleRate / 10))
        let task = Task.detached {
            let clock = ContinuousClock()
            let begin = clock.now
            var frames: AVAudioFramePosition = 0
            while !Task.isCancelled, file.framePosition < file.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
                do {
                    try file.read(into: buffer, frameCount: chunk)
                } catch {
                    onError(error)
                    return
                }
                if buffer.frameLength == 0 { break }
                onBuffer(buffer)
                frames += AVAudioFramePosition(buffer.frameLength)
                let due = begin + .seconds(Double(frames) / format.sampleRate)
                try? await Task.sleep(until: due, clock: clock)
            }
            if !Task.isCancelled { onEnd() }
        }
        mutex.withLock { self.task = task }
    }

    func stop() async {
        let task = mutex.withLock { self.task }
        task?.cancel()
        await task?.value
    }
}
