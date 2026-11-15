import Foundation
import SQLite3

public enum SQLiteValue: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public var intValue: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }

    public var stringValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    public var dataValue: Data? {
        if case .blob(let value) = self { return value }
        return nil
    }
}

public struct Row: Sendable {
    public var values: [String: SQLiteValue]

    public init(values: [String: SQLiteValue] = [:]) {
        self.values = values
    }

    public subscript(_ key: String) -> SQLiteValue? {
        values[key]
    }

    public func int(_ key: String) -> Int64? { values[key]?.intValue }
    public func double(_ key: String) -> Double? { values[key]?.doubleValue }
    public func string(_ key: String) -> String? { values[key]?.stringValue }
    public func data(_ key: String) -> Data? { values[key]?.dataValue }

    public func bool(_ key: String) -> Bool? {
        guard let raw = values[key]?.intValue else { return nil }
        return raw != 0
    }
}

/// A small, dependency-free SQLite wrapper. All access is serialized.
public final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()

    public static let transient = ":memory:"

    public init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &db, flags, nil)
        guard result == SQLITE_OK, let db else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw SphereError.processFailed("sqlite open failed: \(message)")
        }
        self.handle = db
        sqlite3_busy_timeout(db, 5_000)
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA foreign_keys = ON;")
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    @discardableResult
    public func execute(_ sql: String) throws -> [Row] {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else {
            throw SphereError.processFailed("database is closed")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError("prepare '\(sql)'")
        }
        defer { sqlite3_finalize(statement) }

        var rows: [Row] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(readRow(statement))
            } else if result == SQLITE_DONE {
                break
            } else {
                throw sqliteError("step '\(sql)'")
            }
        }
        return rows
    }

    /// Executes a script containing multiple statements (used for migrations).
    public func executeScript(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else {
            throw SphereError.processFailed("database is closed")
        }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            throw SphereError.processFailed("sqlite script: \(message)")
        }
    }

    public func query(_ sql: String, _ parameters: [SQLiteValue] = []) throws -> [Row] {
        try prepareAndRun(sql, parameters, expectRows: true)
    }

    public func run(_ sql: String, _ parameters: [SQLiteValue] = []) throws {
        _ = try prepareAndRun(sql, parameters, expectRows: false)
    }

    public var lastInsertRowID: Int64 {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return 0 }
        return sqlite3_last_insert_rowid(handle)
    }

    public func transaction(_ body: () throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            _ = try? execute("ROLLBACK;")
            throw error
        }
    }

    private func prepareAndRun(_ sql: String, _ parameters: [SQLiteValue], expectRows: Bool) throws -> [Row] {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else {
            throw SphereError.processFailed("database is closed")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError("prepare '\(sql)'")
        }
        defer { sqlite3_finalize(statement) }

        for (index, parameter) in parameters.enumerated() {
            let position = Int32(index + 1)
            switch parameter {
            case .null:
                sqlite3_bind_null(statement, position)
            case .integer(let value):
                sqlite3_bind_int64(statement, position, value)
            case .real(let value):
                sqlite3_bind_double(statement, position, value)
            case .text(let value):
                sqlite3_bind_text(statement, position, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .blob(let value):
                _ = value.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, position, buffer.baseAddress, Int32(buffer.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            }
        }

        var rows: [Row] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(readRow(statement))
            } else if result == SQLITE_DONE {
                break
            } else {
                throw sqliteError("step '\(sql)'")
            }
        }
        return expectRows ? rows : []
    }

    private func readRow(_ statement: OpaquePointer?) -> Row {
        var values: [String: SQLiteValue] = [:]
        let count = sqlite3_column_count(statement)
        for index in 0..<count {
            guard let namePointer = sqlite3_column_name(statement, index) else { continue }
            let name = String(cString: namePointer)
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER:
                values[name] = .integer(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT:
                values[name] = .real(sqlite3_column_double(statement, index))
            case SQLITE_TEXT:
                if let pointer = sqlite3_column_text(statement, index) {
                    values[name] = .text(String(cString: pointer))
                } else {
                    values[name] = .null
                }
            case SQLITE_BLOB:
                if let pointer = sqlite3_column_blob(statement, index) {
                    let length = sqlite3_column_bytes(statement, index)
                    values[name] = .blob(Data(bytes: pointer, count: Int(length)))
                } else {
                    values[name] = .null
                }
            default:
                values[name] = .null
            }
        }
        return Row(values: values)
    }

    private func sqliteError(_ context: String) -> SphereError {
        let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        return .processFailed("sqlite \(context): \(message)")
    }
}
