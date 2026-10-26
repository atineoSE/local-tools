import Foundation
import Testing
@testable import DictateCore

@Suite struct LiveLockTests {
    let dir: URL
    let path: URL

    init() {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictate-lock-\(UUID().uuidString)")
        path = dir.appendingPathComponent("sub/live.pid")
    }

    private func writeLock(_ text: String) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: path, atomically: true, encoding: .utf8)
    }

    private func contents() -> String? {
        try? String(contentsOf: path, encoding: .utf8)
    }

    /// PID of a process that has already exited.
    private func deadPID() throws -> pid_t {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try p.run()
        p.waitUntilExit()
        return p.processIdentifier
    }

    @Test func acquiresWhenMissingAndCreatesDirectory() throws {
        let lock = LiveLock(path: path, pid: 4242, isDictate: { _ in true })
        #expect(try lock.acquire() == .acquired)
        #expect(contents() == "4242\n")
        #expect(lock.owner() == 4242)
    }

    @Test func runningDictateIsReported() throws {
        try writeLock("777\n")
        let lock = LiveLock(path: path, pid: 4242, isDictate: { $0 == 777 })
        #expect(try lock.acquire() == .running(777))
        #expect(contents() == "777\n")  // left for its owner
    }

    @Test func staleLockFromDeadProcessIsReplaced() throws {
        let dead = try deadPID()
        #expect(!LiveLock.isRunningDictate(dead))
        try writeLock("\(dead)\n")
        let lock = LiveLock(path: path, pid: 4242)
        #expect(try lock.acquire() == .acquired)
        #expect(contents() == "4242\n")
    }

    @Test func liveProcessThatIsNotDictateIsStale() throws {
        // This test runner is alive but is not named `dictate`.
        let other = ProcessInfo.processInfo.processIdentifier
        #expect(!LiveLock.isRunningDictate(other))
        try writeLock("\(other)")
        let lock = LiveLock(path: path, pid: 4242)
        #expect(try lock.acquire() == .acquired)
    }

    @Test func garbageAndEmptyLocksAreReplaced() throws {
        for text in ["", "not a pid\n", "-1"] {
            try writeLock(text)
            let lock = LiveLock(path: path, pid: 4242, isDictate: { _ in true })
            #expect(try lock.acquire() == .acquired)
            lock.release()
        }
    }

    @Test func ownPIDInLockIsStale() throws {
        try writeLock("4242\n")
        let lock = LiveLock(path: path, pid: 4242, isDictate: { _ in true })
        #expect(try lock.acquire() == .acquired)
    }

    @Test func releaseRemovesOnlyOwnLock() throws {
        let lock = LiveLock(path: path, pid: 4242, isDictate: { _ in false })
        #expect(try lock.acquire() == .acquired)
        lock.release()
        #expect(!FileManager.default.fileExists(atPath: path.path))

        try writeLock("999\n")
        lock.release()
        #expect(contents() == "999\n")
    }

    @Test func secondAcquirerSeesFirst() throws {
        let first = LiveLock(path: path, pid: 1111, isDictate: { _ in false })
        #expect(try first.acquire() == .acquired)
        let second = LiveLock(path: path, pid: 2222, isDictate: { $0 == 1111 })
        #expect(try second.acquire() == .running(1111))
        first.release()
        #expect(try second.acquire() == .acquired)
    }

    @Test func defaultPathIsInCaches() {
        #expect(LiveLock.defaultPath.path.hasSuffix("/Library/Caches/dictate/live.pid"))
    }
}
