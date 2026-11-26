/**
 * File: GraphDiagramReadingScratch.swift
 * --------------------------------------
 * Layer: Core
 * Description: The working lists a state or class diagram's reader fills and empties at each reading (its name table,
 *              the numbers it keeps by name or by state, the owners of what it reads out of order, the bytes a member
 *              shows), kept per thread so that a reading grows no list it grew before.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The working lists of one reading: emptied, their room kept, before it starts.
struct GraphDiagramReadingLists {
    var names = GraphDiagramNameTable(isASCII: true)
    /// By name: the state or class each names, -1 for none.
    var indexByName: [Int32] = []
    /// By state or class: the composite each is, or the first owner list's entries.
    var firstNumbers: [Int32] = []
    var secondNumbers: [Int32] = []
    var thirdNumbers: [Int32] = []
    var bytes: [UInt8] = []

    /// The lists emptied for a reading of a text that is ASCII or not; a list grown past `largestKept` is let go.
    mutating func reset(isASCII: Bool) {
        names.reset(isASCII: isASCII)
        Self.empty(&indexByName)
        Self.empty(&firstNumbers)
        Self.empty(&secondNumbers)
        Self.empty(&thirdNumbers)
        if bytes.capacity > Self.largestKept { bytes = [] } else { bytes.removeAll(keepingCapacity: true) }
    }

    private static func empty(_ list: inout [Int32]) {
        if list.capacity > largestKept { list = [] } else if !list.isEmpty { list.removeAll(keepingCapacity: true) }
    }

    /// The most entries a list keeps from one reading to the next.
    static let largestKept = 16_384
}

/// Keeps one thread's reading lists from one state or class diagram reading to the next.
final class GraphDiagramReadingScratch {
    private var lists: GraphDiagramReadingLists?

    /// Calls `body` with the thread's lists, emptied for a text that is ASCII or not, and keeps them for the next reading.
    /// A reading that throws gives no lists back; the next one starts with new lists.
    static func withLists<Result>(isASCII: Bool, _ body: (inout GraphDiagramReadingLists) throws(MermaidDiagramReadError) -> Result)
        throws(MermaidDiagramReadError) -> Result {
        let scratch = current
        var lists = scratch.lists.take() ?? GraphDiagramReadingLists()
        lists.reset(isASCII: isASCII)
        let result = try body(&lists)
        scratch.lists = consume lists
        return result
    }

    private static var current: GraphDiagramReadingScratch {
        if let pointer = pthread_getspecific(key) { return Unmanaged<GraphDiagramReadingScratch>.fromOpaque(pointer).takeUnretainedValue() }
        let scratch = GraphDiagramReadingScratch()
        pthread_setspecific(key, Unmanaged.passRetained(scratch).toOpaque())
        return scratch
    }

    private static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { pointer in Unmanaged<GraphDiagramReadingScratch>.fromOpaque(pointer).release() }
        return key
    }()
}
