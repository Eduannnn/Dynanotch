import Foundation
import Darwin

enum AppRestart {
    /// The replacement waits for its parent app to exit before creating NSApplication.
    static func waitForPriorInstance(arguments: [String]) -> Bool {
        guard let i = arguments.firstIndex(of: "--relaunch-after"), arguments.indices.contains(i + 1),
              let pid = Int32(arguments[i + 1]), pid > 1 else { return true }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while kill(pid, 0) == 0 {
            if ProcessInfo.processInfo.systemUptime >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return true
    }
    static func launchReplacement() throws {
        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let replacement = Process()
        replacement.executableURL = executable
        replacement.arguments = ["--relaunch-after", String(ProcessInfo.processInfo.processIdentifier)]
        try replacement.run()
    }
}
