import Foundation
import SphereCore

/// Launches an MCP server as a child process and speaks newline-delimited
/// JSON-RPC 2.0 over stdin/stdout (the MCP stdio transport).
public final class StdioMCPTransport: MCPTransport, @unchecked Sendable {
    private let command: [String]
    private let workingDirectory: URL?
    private let extraEnvironment: [String: String]

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()

    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    private let bufferLock = NSLock()
    private var buffer = Data()
    private var started = false

    public var onLog: ((String) -> Void)?

    public init(command: [String], workingDirectory: URL? = nil, environment: [String: String]? = nil) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.extraEnvironment = environment ?? [:]

        var captured: AsyncThrowingStream<Data, Error>.Continuation!
        self.stream = AsyncThrowingStream { captured = $0 }
        self.continuation = captured
    }

    public var incoming: AsyncThrowingStream<Data, Error> {
        stream
    }

    public func start() throws {
        guard !started else { return }
        guard let executable = command.first, !executable.isEmpty else {
            throw SphereError.transportUnavailable
        }
        started = true

        if executable.hasPrefix("/") || executable.hasPrefix("./") {
            if executable.hasPrefix("./"), let workingDirectory {
                process.executableURL = workingDirectory.appendingPathComponent(String(executable.dropFirst(2)))
            } else {
                process.executableURL = URL(fileURLWithPath: executable)
            }
            process.arguments = Array(command.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command
        }

        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            guard !data.isEmpty else {
                self.continuation.finish()
                return
            }
            self.bufferLock.lock()
            self.buffer.append(data)
            let lines = self.takeCompleteLines()
            self.bufferLock.unlock()
            for line in lines {
                self.continuation.yield(line)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.onLog?(text)
        }

        process.terminationHandler = { [weak self] process in
            self?.onLog?("[sphere] MCP process exited with status \(process.terminationStatus)\n")
            self?.continuation.finish()
        }

        do {
            try process.run()
        } catch {
            started = false
            throw SphereError.processFailed("could not launch MCP process: \(error.localizedDescription)")
        }
    }

    public func send(_ message: Data) throws {
        guard started else { throw SphereError.transportUnavailable }
        var payload = message
        payload.append(0x0A)
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: payload)
        } catch {
            throw SphereError.processFailed("could not write to MCP stdin: \(error.localizedDescription)")
        }
    }

    public func stop() {
        guard started else { return }
        started = false
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
        continuation.finish()
    }

    private func takeCompleteLines() -> [Data] {
        var lines: [Data] = []
        while let index = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<index]
            buffer.removeSubrange(buffer.startIndex...index)
            if !line.isEmpty {
                lines.append(Data(line))
            }
        }
        return lines
    }
}
