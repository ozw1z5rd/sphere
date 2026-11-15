import Foundation

/// Runs a child process with a hard timeout and bounded output. Arguments are
/// passed as an argv array: no shell is ever involved.
struct ProcessResult: Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var timedOut: Bool
    var truncated: Bool
}

enum ProcessRunner {
    static func run(
        executable: URL,
        arguments: [String],
        cwd: URL,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 30,
        maxOutputBytes: Int = 200_000
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()

        var stdoutData = Data()
        var stderrData = Data()
        let group = DispatchGroup()
        let lock = NSLock()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); stdoutData = data; lock.unlock()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); stderrData = data; lock.unlock()
            group.leave()
        }

        var timedOut = false
        let deadline = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut = true
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        process.waitUntilExit()
        deadline.cancel()
        group.wait()

        var truncated = false
        func bounded(_ data: Data) -> String {
            if data.count > maxOutputBytes {
                truncated = true
                return String(decoding: data.prefix(maxOutputBytes), as: UTF8.self)
                    + "\n… output truncated at \(maxOutputBytes) bytes"
            }
            return String(decoding: data, as: UTF8.self)
        }

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: bounded(stdoutData),
            stderr: bounded(stderrData),
            timedOut: timedOut,
            truncated: truncated
        )
    }

    /// Environment for child processes: keeps locale/PATH, drops anything that
    /// looks like a credential and replaces HOME with a temporary directory.
    static func sanitizedEnvironment(home: URL? = nil, extra: [String: String] = [:]) -> [String: String] {
        let allowed = ["PATH", "LANG", "LC_ALL", "LC_CTYPE", "TERM", "TMPDIR", "SHELL", "USER", "LOGNAME", "SYSTEM_VERSION_COMPAT"]
        let sensitive = ["KEY", "TOKEN", "SECRET", "PASSWORD", "PASSWD", "CREDENTIAL", "AUTH", "API"]
        var result: [String: String] = [:]
        for (key, value) in ProcessInfo.processInfo.environment {
            let upper = key.uppercased()
            if sensitive.contains(where: { upper.contains($0) }) { continue }
            if allowed.contains(key) {
                result[key] = value
            }
        }
        if result["PATH"] == nil {
            result["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        if let home {
            result["HOME"] = home.path
            result["TMPDIR"] = home.appendingPathComponent("tmp").path
        }
        for (key, value) in extra {
            result[key] = value
        }
        return result
    }
}
