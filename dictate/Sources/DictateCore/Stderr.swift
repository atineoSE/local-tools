import Foundation

/// Writes a line to stderr (progress and errors never go to stdout).
public func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
