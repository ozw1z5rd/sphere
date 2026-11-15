import Foundation

/// Transport abstraction so the in-house stdio implementation can later be
/// swapped for the official MCP Swift SDK.
public protocol MCPTransport: AnyObject {
    func start() throws
    func send(_ message: Data) throws
    var incoming: AsyncThrowingStream<Data, Error> { get }
    func stop()
}
