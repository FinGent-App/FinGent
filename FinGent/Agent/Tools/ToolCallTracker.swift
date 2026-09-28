// FinGent/Agent/Tools/ToolCallTracker.swift
//
// Thread-safe tracker to observe and record tool executions by Apple FoundationModels.

import Foundation

final class ToolCallTracker: @unchecked Sendable {
    static let shared = ToolCallTracker()

    struct ToolRecord: Sendable {
        let name: String
        let arguments: [String: String]
    }

    private let lock = NSLock()
    private var executedRecords: [ToolRecord] = []

    private init() {}

    /// Records the name of a tool that was executed by the agent session
    func record(toolName: String, arguments: [String: String] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        executedRecords.append(ToolRecord(name: toolName, arguments: arguments))
    }

    /// Drains and clears the list of executed tool records for reporting trace
    func drainRecords() -> [ToolRecord] {
        lock.lock()
        defer { lock.unlock() }
        let current = executedRecords
        executedRecords = []
        return current
    }

    /// Drains and returns just the tool names
    func drain() -> [String] {
        let records = drainRecords()
        var uniqueNames: [String] = []
        for r in records {
            if !uniqueNames.contains(r.name) {
                uniqueNames.append(r.name)
            }
        }
        return uniqueNames
    }

    /// Clears any lingering tool records
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        executedRecords = []
    }
}
