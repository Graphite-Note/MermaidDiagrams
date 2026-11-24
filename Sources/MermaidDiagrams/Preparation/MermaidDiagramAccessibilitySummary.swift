/**
 * File: MermaidDiagramAccessibilitySummary.swift
 * ----------------------------------------------
 * Layer: Core
 * Description: The parts of what a screen reader says of a diagram, made the first time they are read, on whatever
 *              thread reads them, and kept: preparing a diagram no longer builds a summary nobody may ask for.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation

/// A summary's parts, known already or made from the diagram the work captured.
enum MermaidDiagramAccessibilitySummary: Sendable {
    case made([String])
    case later(MermaidDiagramAccessibilityLaterSummary)

    var parts: [String] {
        switch self {
        case .made(let parts): parts
        case .later(let summary): summary.parts
        }
    }

    /// Whether the parts are made yet, for the tests that check the preparation leaves them to the first reader.
    var isMade: Bool {
        switch self {
        case .made: true
        case .later(let summary): summary.isMade
        }
    }
}

/// The work that makes a summary, run once by its first reader under a lock, and the parts it made, kept in its place.
/// The work never reads this store again, so holding the lock while it runs cannot wait on itself.
final class MermaidDiagramAccessibilityLaterSummary: @unchecked Sendable {
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var making: (@Sendable () -> [String])?
    private var made: [String] = []

    init(_ making: @escaping @Sendable () -> [String]) {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        self.making = making
    }

    deinit {
        lock.deallocate()
    }

    var parts: [String] {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if let making {
            made = making()
            self.making = nil
        }
        return made
    }

    var isMade: Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return making == nil
    }
}
