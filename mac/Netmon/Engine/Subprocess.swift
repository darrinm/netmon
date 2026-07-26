import Foundation

enum Subprocess {
    /// Runs an executable to completion and returns its stdout as a string.
    /// Blocking — call off the main actor.
    static func capture(_ path: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            // Drain *before* waiting. A pipe holds ~64KB; once it fills, the
            // child blocks writing and `waitUntilExit()` blocks on a child that
            // can never finish — a deadlock that only shows up once output
            // outgrows the buffer (a full `ps` listing is ~270KB).
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
