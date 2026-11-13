import Foundation

/// Writes a line to stderr (progress and errors never go to stdout).
/// While the status line is showing, it is cleared first and redrawn below the message.
public func printError(_ message: String) {
    Status.shared.write(message + "\n")
}

/// A one-line progress display on stderr: a spinner, the running stages, and the elapsed time,
/// redrawn ten times a second. Shown only when stderr is a terminal, so pipes, logs and the
/// keyboard-shortcut run get no control characters. stdout is never touched.
public final class Status: @unchecked Sendable {
    public static let shared = Status()

    /// What a stage shows after its name, read at each redraw ("42%", "2/5", or "" for no detail).
    public typealias Detail = @Sendable () -> String

    private let lock = NSLock()
    private let enabled: Bool
    /// A copy of stderr taken at start, so `Stderr.dropping` can redirect fd 2 without hiding dictate's own output.
    private let out = FileHandle(fileDescriptor: dup(STDERR_FILENO), closeOnDealloc: true)
    private var stages: [(name: String, detail: Detail)] = []
    private var timer: DispatchSourceTimer?
    /// Set when the first stage appears; the clock then counts the whole run.
    private var started: Date?
    private var frame = 0
    private var drawn = false

    init(enabled: Bool = isatty(STDERR_FILENO) == 1 && ProcessInfo.processInfo.environment["TERM"] != "dumb") {
        self.enabled = enabled
    }

    /// Adds a stage, or replaces the detail of a running stage with the same name.
    public func set(_ name: String, _ detail: @escaping Detail = { "" }) {
        guard enabled else { return }
        lock.withLock {
            if let i = stages.firstIndex(where: { $0.name == name }) {
                stages[i].detail = detail
            } else {
                stages.append((name, detail))
            }
            if timer == nil { startTimer() }
            draw()
        }
    }

    /// Shows a fixed detail, such as "2/5".
    public func set(_ name: String, text: String) {
        set(name) { text }
    }

    /// Shows a fraction of 0…1 as a percentage.
    public func set(_ name: String, fraction: Double) {
        set(name, text: Self.percent(fraction))
    }

    /// Removes a stage. The line goes away when no stage is left.
    public func done(_ name: String) {
        guard enabled else { return }
        lock.withLock {
            stages.removeAll { $0.name == name }
            if stages.isEmpty { stopTimer() } else { draw() }
        }
    }

    /// Removes every stage and clears the line. Call before printing the result.
    public func finish() {
        guard enabled else { return }
        lock.withLock {
            stages.removeAll()
            stopTimer()
        }
    }

    func write(_ text: String) {
        lock.withLock {
            if drawn { clear() }
            out.write(Data(text.utf8))
            if !stages.isEmpty { draw() }
        }
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded(.down)))%"
    }

    /// The line without control characters: "⠋ Transcribing 42% · Finding speakers 80% · 0:12".
    static func line(frame: Int, stages: [(name: String, detail: String)], elapsed: TimeInterval) -> String {
        let spinner = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
        let parts = stages.map { $0.detail.isEmpty ? $0.name : "\($0.name) \($0.detail)" }
        let seconds = Int(elapsed)
        let clock = String(format: "%d:%02d", seconds / 60, seconds % 60)
        return "\(spinner[frame % spinner.count]) \((parts + [clock]).joined(separator: " · "))"
    }

    // The methods below run with `lock` held.

    private func startTimer() {
        if started == nil { started = Date() }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.withLock {
                self.frame += 1
                if !self.stages.isEmpty { self.draw() }
            }
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        if drawn { clear() }
    }

    private func draw() {
        var text = Self.line(frame: frame, stages: stages.map { ($0.name, $0.detail()) }, elapsed: Date().timeIntervalSince(started ?? Date()))
        // A line that wraps cannot be cleared with \r, so cut it to the terminal width.
        var size = winsize()
        if ioctl(STDERR_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 1, text.count >= Int(size.ws_col) {
            text = String(text.prefix(Int(size.ws_col) - 2)) + "…"
        }
        out.write(Data("\r\u{1B}[2K\(text)".utf8))
        drawn = true
    }

    private func clear() {
        out.write(Data("\r\u{1B}[2K".utf8))
        drawn = false
    }
}

public enum Stderr {
    /// Runs `body` with fd 2 going through a pipe that drops lines starting with `prefix` and passes
    /// the rest on. For library output that cannot be turned off (FluidAudio's "[Profiling]" lines),
    /// which would otherwise break into the status line.
    public static func dropping<T>(prefix: String, _ body: () async throws -> T) async throws -> T {
        let status = Status.shared // takes its copy of stderr before the redirect
        let pipe = Pipe()
        fflush(stderr)
        let saved = dup(STDERR_FILENO)
        guard saved >= 0, dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO) >= 0 else {
            if saved >= 0 { close(saved) }
            return try await body()
        }
        let reader = DispatchGroup()
        reader.enter()
        Thread.detachNewThread {
            defer { reader.leave() }
            var pending = Data()
            func flush(_ line: Data) {
                let text = String(decoding: line, as: UTF8.self)
                if !text.hasPrefix(prefix) { status.write(text) }
            }
            while case let chunk = pipe.fileHandleForReading.availableData, !chunk.isEmpty {
                pending.append(chunk)
                while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    flush(pending[...newline])
                    pending = Data(pending[pending.index(after: newline)...])
                }
            }
            if !pending.isEmpty { flush(pending) }
        }
        let result: Result<T, any Error>
        do { result = .success(try await body()) } catch { result = .failure(error) }
        fflush(stderr)
        dup2(saved, STDERR_FILENO)
        close(saved)
        try? pipe.fileHandleForWriting.close() // last write end: the reader sees end of file
        await withCheckedContinuation { done in reader.notify(queue: .global()) { done.resume() } }
        return try result.get()
    }
}
