import Foundation

public enum Live {
    /// Runs live mode and returns the process exit code. Stub: not implemented.
    public static func run(options: Options) async -> Int32 {
        printError("live mode not implemented yet")
        return 1
    }
}
